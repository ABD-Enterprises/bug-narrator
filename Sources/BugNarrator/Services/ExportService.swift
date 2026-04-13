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

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .github,
            apiKey: apiKey,
            model: model
        ) { issue in
            try await self.gitHubProvider.findOpenIssues(matching: issue, configuration: configuration)
        }
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .jira,
            apiKey: apiKey,
            model: model
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
}

struct TrackerIssueCandidate: Equatable {
    let remoteIdentifier: String
    let title: String
    let summary: String
    let remoteURL: URL?
}

actor SimilarIssueReviewService {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
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
        fetchCandidates: @escaping @Sendable (ExtractedIssue) async throws -> [TrackerIssueCandidate]
    ) async throws -> IssueExportReview {
        var items: [IssueExportReviewItem] = []

        for issue in issues {
            let candidates = try await fetchCandidates(issue)
            let matches = try await compare(issue: issue, candidates: candidates, apiKey: apiKey, model: model)
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
        model: String
    ) async throws -> [SimilarIssueMatch] {
        guard !candidates.isEmpty else {
            return []
        }

        let request = try makeRequest(
            endpoint: endpoint,
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
