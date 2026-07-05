import Foundation

struct TrackerIssueCandidate: Equatable {
    let remoteIdentifier: String
    let title: String
    let summary: String
    let remoteURL: URL?
}

/// Helpers shared by the tracker export providers (Jira, GitHub) whose
/// implementations are byte-identical apart from the provider's display name.
enum TrackerExportSupport {
    /// Reserved words that act as operators/keywords in GitHub issue search and
    /// in Jira's JQL. The term tokenizer already strips all non-alphanumeric
    /// characters (so quotes, colons, and slashes can never reach the query),
    /// but a 3+ character keyword like `AND`/`NOT`/`ORDER` would otherwise
    /// survive as a bare token and subtly broaden or alter the duplicate search.
    /// These are common stop-words in prose, so dropping them does not weaken
    /// the keyword match for real issue text.
    private static let reservedSearchWords: Set<String> = [
        "and", "or", "not", "in", "is", "was", "null", "empty",
        "order", "by", "changed", "during", "before", "after", "on"
    ]

    /// Builds a short search phrase from an issue's most significant terms, used
    /// to look for potential duplicate issues before exporting. The phrase is a
    /// space-separated list of literal keyword terms; it must never be able to
    /// introduce a search operator/qualifier.
    static func searchTerms(for issue: ExtractedIssue) -> String {
        let source = [issue.title, issue.component, issue.summary]
            .compactMap { $0 }
            .joined(separator: " ")
        let significantTerms = source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !reservedSearchWords.contains($0.lowercased()) }

        return significantTerms.prefix(6).joined(separator: " ")
    }

    /// Wraps an export error with the count of issues that succeeded before the
    /// failure, so a partial export reports how much work already landed.
    static func partialExportError(
        _ error: AppError,
        providerName: String,
        successfulCount: Int
    ) -> AppError {
        guard successfulCount > 0 else {
            return error
        }

        return .exportFailure(
            "\(providerName) exported \(successfulCount) issue\(successfulCount == 1 ? "" : "s") before failing. \(error.userMessage)"
        )
    }

    /// Parses the integer (delta-seconds) form of an HTTP `Retry-After` header.
    /// The HTTP-date form is treated as absent.
    static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces),
              let seconds = Int(raw),
              seconds >= 0 else {
            return nil
        }
        return seconds
    }

    /// A "wait and retry" suffix for a rate-limit message, using the Retry-After
    /// hint when one is available.
    static func retryAfterSuffix(_ seconds: Int?) -> String {
        if let seconds {
            return " Wait \(seconds)s and try again."
        }
        return " Wait a moment and try again."
    }

    /// Whether an HTTP status warrants a retry (secondary rate limit / server error).
    static func isTransientStatus(_ status: Int) -> Bool {
        status == 429 || (500...599).contains(status)
    }

    /// Backoff before the next retry: honor `Retry-After` if present, else
    /// exponential on the configured base (attempt is 1-based for the attempt
    /// that just failed).
    static func retryDelay(attempt: Int, retryAfterSeconds: Int?, base: Duration) -> Duration {
        if let retryAfterSeconds, retryAfterSeconds > 0 {
            return .seconds(retryAfterSeconds)
        }
        let multiplier = 1 << max(0, attempt - 1)
        return base * multiplier
    }
}

/// Bounds retry of a single per-issue tracker create. POST issue-creation is not
/// blindly idempotent, so retries are only safe because the export loop reconciles
/// by the `bugnarrator-export-id` marker before re-creating (#502).
struct ExportRetryConfiguration: Sendable {
    let maxAttempts: Int
    let baseDelay: Duration

    static let `default` = ExportRetryConfiguration(maxAttempts: 3, baseDelay: .milliseconds(500))
    /// No real backoff — for tests that simulate transient-then-success.
    static let immediate = ExportRetryConfiguration(maxAttempts: 3, baseDelay: .zero)
}

/// Outcome of a single create attempt, classified for the retry loop.
enum ExportCreateOutcome {
    case success(remoteIdentifier: String, remoteURL: URL?)
    case transient(AppError, retryAfterSeconds: Int?)
    case permanent(AppError)
}

/// The provider-specific naming the shared retry runner needs. Everything else
/// in the retry state machine is identical across providers, so only the display
/// name, destination, and the provider-prefixed log-event keys vary here.
struct TrackerExportRetryContext: Sendable {
    /// Human-facing provider name, e.g. "GitHub" / "Jira".
    let displayName: String
    let destination: ExportDestination
    /// Log event emitted on a successful create, e.g. "github_issue_exported".
    let exportedLogEvent: String
    /// Log event emitted on a failed create attempt, e.g. "github_export_failed".
    let failedLogEvent: String
    /// Log event emitted when reconciliation itself fails, e.g.
    /// "github_export_reconciliation_failed".
    let reconciliationFailedLogEvent: String
}

extension TrackerExportSupport {
    /// The shared, dup-safe create-with-retry state machine for tracker exports
    /// (#502). The two providers ran byte-identical copies of this; it now lives
    /// in one place so the dup-safety invariant is maintained once.
    ///
    /// Provider-specific work is injected:
    /// - `attemptCreate` performs a single create POST and classifies the result
    ///   as success / transient / permanent.
    /// - `reconcile` searches for an already-created issue by its export marker.
    ///
    /// Invariant: a created-but-unacknowledged issue is never duplicated. On a
    /// transient failure, reconciliation runs *before* any retry create; the
    /// pending receipt is preserved across transient retries and cleared only on a
    /// confirmed permanent failure.
    ///
    /// Runs in the *caller's* isolation domain (`isolation: #isolation`), so when
    /// a provider actor delegates here the state machine stays on that actor — the
    /// receipt transitions (`markPending` set by the caller, then `markSucceeded`
    /// here) keep the exact ordering they had when this code lived inline in each
    /// provider, with no new interleaving window.
    static func runCreateWithRetry(
        issueID: UUID,
        fingerprint: String,
        targetIdentity: String,
        successfulCount: Int,
        configuration retryConfiguration: ExportRetryConfiguration,
        receiptStore: any ExportReceiptStoring,
        logger: DiagnosticsLogger,
        context: TrackerExportRetryContext,
        isolation: isolated (any Actor)? = #isolation,
        attemptCreate: () async -> ExportCreateOutcome,
        reconcile: () async throws -> ExportResult?
    ) async throws -> ExportResult {
        for attempt in 1...retryConfiguration.maxAttempts {
            switch await attemptCreate() {
            case .success(let remoteIdentifier, let remoteURL):
                try await receiptStore.markSucceeded(
                    fingerprint: fingerprint,
                    sourceIssueID: issueID,
                    destination: context.destination,
                    targetIdentity: targetIdentity,
                    remoteIdentifier: remoteIdentifier,
                    remoteURL: remoteURL
                )
                logger.info(
                    context.exportedLogEvent,
                    "Exported one issue to \(context.displayName).",
                    metadata: ["source_issue_id": issueID.uuidString, "remote_identifier": remoteIdentifier]
                )
                return ExportResult(
                    sourceIssueID: issueID,
                    destination: context.destination,
                    remoteIdentifier: remoteIdentifier,
                    remoteURL: remoteURL
                )

            case .transient(let createError, let retryAfterSeconds):
                logger.error(
                    context.failedLogEvent,
                    createError.userMessage,
                    metadata: [
                        "source_issue_id": issueID.uuidString,
                        "attempt": "\(attempt)",
                        "transient": "true"
                    ]
                )
                do {
                    if let reconciled = try await reconcile() {
                        return reconciled
                    }
                } catch {
                    logger.warning(
                        context.reconciliationFailedLogEvent,
                        (error as? AppError)?.userMessage ?? error.localizedDescription,
                        metadata: ["source_issue_id": issueID.uuidString]
                    )
                    throw partialExportError(createError, providerName: context.displayName, successfulCount: successfulCount)
                }

                if attempt < retryConfiguration.maxAttempts {
                    let delay = retryDelay(
                        attempt: attempt,
                        retryAfterSeconds: retryAfterSeconds,
                        base: retryConfiguration.baseDelay
                    )
                    if delay > .zero {
                        try? await Task.sleep(for: delay)
                    }
                    continue
                }
                throw partialExportError(createError, providerName: context.displayName, successfulCount: successfulCount)

            case .permanent(let error):
                logger.error(
                    context.failedLogEvent,
                    error.userMessage,
                    metadata: ["source_issue_id": issueID.uuidString, "transient": "false"]
                )
                if let reconciled = try? await reconcile() {
                    return reconciled
                }
                try? await receiptStore.clearReceipt(for: fingerprint)
                throw partialExportError(error, providerName: context.displayName, successfulCount: successfulCount)
            }
        }

        throw partialExportError(
            .exportFailure("\(context.displayName) export did not complete."),
            providerName: context.displayName,
            successfulCount: successfulCount
        )
    }
}
