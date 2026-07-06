import Foundation

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
