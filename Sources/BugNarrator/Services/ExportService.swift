import Foundation

actor ExportService: IssueExporting {
    private let gitHubProvider: GitHubExportProvider
    private let jiraProvider: JiraExportProvider
    private let similarIssueReviewService: SimilarIssueReviewService

    init(
        gitHubProvider: GitHubExportProvider = GitHubExportProvider(),
        jiraProvider: JiraExportProvider = JiraExportProvider(),
        similarIssueReviewService: SimilarIssueReviewService = SimilarIssueReviewService()
    ) {
        self.gitHubProvider = gitHubProvider
        self.jiraProvider = jiraProvider
        self.similarIssueReviewService = similarIssueReviewService
    }

    func fetchGitHubRepositories(
        token: String
    ) async throws -> [GitHubRepositoryOption] {
        try await gitHubProvider.fetchRepositories(token: token)
    }

    func fetchJiraProjects(
        _ configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        try await jiraProvider.fetchProjects(configuration: configuration)
    }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        try await jiraProvider.fetchIssueTypes(for: projectKey, projectID: projectID, configuration: configuration)
    }

    func validateGitHubConfiguration(
        _ configuration: GitHubExportConfiguration
    ) async throws {
        try await gitHubProvider.validate(configuration: configuration)
    }

    func validateJiraConfiguration(
        _ configuration: JiraExportConfiguration
    ) async throws {
        try await jiraProvider.validate(configuration: configuration)
    }

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .github,
            apiKey: apiKey,
            model: model,
            apiBaseURL: apiBaseURL
        ) { issue in
            try await self.gitHubProvider.findOpenIssues(matching: issue, configuration: configuration)
        }
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .jira,
            apiKey: apiKey,
            model: model,
            apiBaseURL: apiBaseURL
        ) { issue in
            try await self.jiraProvider.findOpenIssues(matching: issue, configuration: configuration)
        }
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        try await gitHubProvider.export(issues: issues, session: session, configuration: configuration)
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        try await jiraProvider.export(issues: issues, session: session, configuration: configuration)
    }

    func exportHistory() async throws -> [ExportReceipt] {
        try await ExportReceiptStore().allReceipts()
    }
}

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

actor SimilarIssueReviewService {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: configuration)
        }
    }

    func prepareReview(
        issues: [ExtractedIssue],
        session reviewSession: TranscriptSession,
        destination: ExportDestination,
        apiKey: String,
        model: String,
        apiBaseURL: URL = URL(string: "https://api.openai.com")!,
        fetchCandidates: @escaping @Sendable (ExtractedIssue) async throws -> [TrackerIssueCandidate]
    ) async throws -> IssueExportReview {
        var items: [IssueExportReviewItem] = []

        for issue in issues {
            let candidates = try await fetchCandidates(issue)
            let matches = try await compare(
                issue: issue,
                candidates: candidates,
                apiKey: apiKey,
                model: model,
                apiBaseURL: apiBaseURL
            )
            items.append(IssueExportReviewItem(issue: issue, matches: matches))
        }

        return IssueExportReview(
            destination: destination,
            sessionID: reviewSession.id,
            items: items
        )
    }

    private func compare(
        issue: ExtractedIssue,
        candidates: [TrackerIssueCandidate],
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> [SimilarIssueMatch] {
        guard !candidates.isEmpty else {
            return []
        }

        let request = try makeRequest(
            endpoint: OpenAIEndpointBuilder.endpoint(for: "v1/chat/completions", baseURL: apiBaseURL),
            issue: issue,
            candidates: candidates,
            apiKey: apiKey,
            model: model
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("The similar issue review returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIErrorMapper.mapResponse(
                statusCode: httpResponse.statusCode,
                data: data,
                fallback: AppError.exportFailure
            )
        }

        let completion = try JSONDecoder().decode(TrackerMatchCompletionResponse.self, from: data)
        guard let message = completion.choices.first?.message else {
            return []
        }

        if let refusal = message.refusal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refusal.isEmpty {
            throw AppError.exportFailure(refusal)
        }

        guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return []
        }

        let payload = try TrackerMatchPayload.parse(from: content)
        let candidateIndex = Dictionary(uniqueKeysWithValues: candidates.map { ($0.remoteIdentifier.lowercased(), $0) })

        return payload.matches.compactMap { match in
            guard let candidate = candidateIndex[match.remoteIdentifier.lowercased()] else {
                return nil
            }

            return SimilarIssueMatch(
                remoteIdentifier: candidate.remoteIdentifier,
                title: candidate.title,
                summary: candidate.summary,
                remoteURL: candidate.remoteURL,
                confidence: match.confidence,
                reasoning: match.reasoning
            )
        }
    }

    private func makeRequest(
        endpoint: URL,
        issue: ExtractedIssue,
        candidates: [TrackerIssueCandidate],
        apiKey: String,
        model: String
    ) throws -> URLRequest {
        let body = try JSONEncoder().encode(
            TrackerMatchChatCompletionRequest(
                model: model,
                temperature: 0,
                responseFormat: .jsonObject,
                messages: [
                    .init(
                        role: "system",
                        content: """
                        You compare a new software issue report against existing tracker issues.
                        Return strict JSON with the top likely matches in a matches array.
                        Each match must include remoteIdentifier, confidence, reasoning.
                        Only include matches when the candidate is plausibly a duplicate or strongly related issue.
                        Confidence must be a decimal from 0 to 1.
                        Limit output to at most 3 matches sorted by highest confidence first.
                        """
                    ),
                    .init(
                        role: "user",
                        content: makePrompt(issue: issue, candidates: candidates)
                    )
                ]
            )
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func makePrompt(issue: ExtractedIssue, candidates: [TrackerIssueCandidate]) -> String {
        var lines: [String] = [
            "New issue:",
            "- Title: \(issue.title)",
            "- Summary: \(issue.summary)",
            "- Evidence: \(issue.evidenceExcerpt)",
            "- Severity: \(issue.severity.rawValue)",
            "- Category: \(issue.category.rawValue)",
            "- Deduplication hint: \(issue.deduplicationHint)"
        ]

        if let component = issue.component, !component.isEmpty {
            lines.append("- Component: \(component)")
        }

        if !issue.reproductionSteps.isEmpty {
            lines.append("- Reproduction steps:")
            for (index, step) in issue.reproductionSteps.enumerated() {
                lines.append("  \(index + 1). \(step.instruction)")
            }
        }

        lines.append("")
        lines.append("Candidate tracker issues:")

        for candidate in candidates {
            lines.append("- \(candidate.remoteIdentifier)")
            lines.append("  Title: \(candidate.title)")
            if !candidate.summary.isEmpty {
                lines.append("  Summary: \(candidate.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

private struct TrackerMatchChatCompletionRequest: Encodable {
    let model: String
    let temperature: Double
    let responseFormat: TrackerMatchResponseFormat
    let messages: [TrackerMatchChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case responseFormat = "response_format"
        case messages
    }
}

private struct TrackerMatchResponseFormat: Encodable {
    let type: String

    static let jsonObject = TrackerMatchResponseFormat(type: "json_object")
}

private struct TrackerMatchChatMessage: Encodable {
    let role: String
    let content: String
}

private struct TrackerMatchCompletionResponse: Decodable {
    let choices: [TrackerMatchChoice]
}

private struct TrackerMatchChoice: Decodable {
    let message: TrackerMatchMessage
}

private struct TrackerMatchMessage: Decodable {
    let content: String?
    let refusal: String?

    enum CodingKeys: String, CodingKey {
        case content
        case refusal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refusal = try? container.decodeIfPresent(String.self, forKey: .refusal)

        if let content = try? container.decodeIfPresent(String.self, forKey: .content) {
            self.content = content
            return
        }

        if let parts = try? container.decodeIfPresent([TrackerMatchMessagePart].self, forKey: .content) {
            let joined = parts.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
            self.content = joined.isEmpty ? nil : joined
            return
        }

        content = nil
    }
}

private struct TrackerMatchMessagePart: Decodable {
    let text: String?
}

private struct TrackerMatchPayload {
    struct Match: Equatable {
        let remoteIdentifier: String
        let confidence: Double
        let reasoning: String
    }

    let matches: [Match]

    static func parse(from content: String) throws -> TrackerMatchPayload {
        let normalized = stripMarkdownFence(from: content) ?? content
        let data = Data(normalized.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw AppError.exportFailure("Similar issue review returned an unexpected format.")
        }

        let rawMatches = dictionary["matches"] as? [[String: Any]] ?? []
        let matches = rawMatches.compactMap { value -> Match? in
            guard let remoteIdentifier = (value["remoteIdentifier"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !remoteIdentifier.isEmpty else {
                return nil
            }

            let confidence = value["confidence"] as? Double
                ?? (value["confidence"] as? NSNumber)?.doubleValue
                ?? 0
            let reasoning = (value["reasoning"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            return Match(
                remoteIdentifier: remoteIdentifier,
                confidence: confidence,
                reasoning: reasoning
            )
        }

        return TrackerMatchPayload(matches: matches)
    }

    private static func stripMarkdownFence(from content: String) -> String? {
        guard content.hasPrefix("```") else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            return nil
        }

        guard let closingFenceIndex = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "```" }),
              closingFenceIndex > lines.startIndex else {
            return nil
        }

        let bodyLines = lines[(lines.startIndex + 1)..<closingFenceIndex]
        return bodyLines.joined(separator: "\n")
    }
}
