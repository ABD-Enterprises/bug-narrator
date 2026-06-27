import Foundation

actor GitHubExportProvider {
    private let session: URLSession
    private let receiptStore: any ExportReceiptStoring
    private let logger = DiagnosticsLogger(category: .export)
    private let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(
        session: URLSession? = nil,
        receiptStore: any ExportReceiptStoring = ExportReceiptStore()
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
        self.receiptStore = receiptStore
    }

    func fetchRepositories(token: String) async throws -> [GitHubRepositoryOption] {
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.exportConfigurationMissing(
                "GitHub repository discovery requires a personal access token."
            )
        }

        var page = 1
        var repositories: [GitHubRepositoryOption] = []

        while true {
            let request = try makeRepositoryListRequest(token: token, page: page)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.exportFailure("GitHub returned an invalid response.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapGitHubError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    configuration: GitHubExportConfiguration(
                        token: token,
                        owner: "",
                        repository: "",
                        labels: []
                    )
                )
            }

            let payload = try JSONDecoder().decode([GitHubRepositoryListItem].self, from: data)
            repositories.append(
                contentsOf: payload.compactMap { repo in
                    guard repo.hasIssues else {
                        return nil
                    }

                    if let permissions = repo.permissions,
                       !permissions.canCreateIssues {
                        return nil
                    }

                    return GitHubRepositoryOption(
                        repositoryID: repo.nodeID,
                        owner: repo.owner.login,
                        name: repo.name,
                        description: repo.description?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    )
                }
            )

            if payload.count < 100 {
                break
            }

            page += 1
        }

        return repositories.sorted {
            $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
        }
    }

    func export(
        issues: [ExtractedIssue],
        session reviewSession: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "GitHub export requires a personal access token, repository owner, and repository name."
            )
        }

        logger.info(
            "github_export_requested",
            "Exporting selected issues to GitHub.",
            metadata: [
                "issue_count": "\(issues.count)",
                "repository": "\(configuration.owner)/\(configuration.repository)",
                "session_id": reviewSession.id.uuidString
            ]
        )

        var results: [ExportResult] = []

        for issue in issues {
            let fingerprint = TrackerExportFingerprint.make(
                destination: .github,
                targetIdentity: configuration.targetIdentity,
                sessionID: reviewSession.id,
                issueID: issue.id
            )

            if let existingResult = try await existingExportResult(
                fingerprint: fingerprint,
                sourceIssueID: issue.id,
                configuration: configuration
            ) {
                results.append(existingResult)
                continue
            }

            try await receiptStore.markPending(
                fingerprint: fingerprint,
                sourceIssueID: issue.id,
                destination: .github,
                targetIdentity: configuration.targetIdentity
            )

            let request = try makeURLRequest(
                issue: issue,
                session: reviewSession,
                configuration: configuration,
                exportFingerprint: fingerprint
            )

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.exportFailure("GitHub returned an invalid response.")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw mapGitHubError(
                        statusCode: httpResponse.statusCode,
                        data: data,
                        configuration: configuration,
                        retryAfterSeconds: TrackerExportSupport.retryAfterSeconds(from: httpResponse)
                    )
                }

                let payload = try JSONDecoder().decode(GitHubIssueResponse.self, from: data)
                try await receiptStore.markSucceeded(
                    fingerprint: fingerprint,
                    sourceIssueID: issue.id,
                    destination: .github,
                    targetIdentity: configuration.targetIdentity,
                    remoteIdentifier: "#\(payload.number)",
                    remoteURL: payload.htmlURL
                )
                let result = ExportResult(
                    sourceIssueID: issue.id,
                    destination: .github,
                    remoteIdentifier: "#\(payload.number)",
                    remoteURL: payload.htmlURL
                )
                results.append(result)
                logger.info(
                    "github_issue_exported",
                    "Exported one issue to GitHub.",
                    metadata: [
                        "source_issue_id": issue.id.uuidString,
                        "remote_identifier": "#\(payload.number)"
                    ]
                )
            } catch {
                logger.error(
                    "github_export_failed",
                    (error as? AppError)?.userMessage ?? error.localizedDescription,
                    metadata: [
                        "successful_count": "\(results.count)",
                        "source_issue_id": issue.id.uuidString
                    ]
                )
                do {
                    if let reconciledResult = try await reconcilePendingExport(
                        fingerprint: fingerprint,
                        sourceIssueID: issue.id,
                        configuration: configuration
                    ) {
                        results.append(reconciledResult)
                        continue
                    }
                } catch {
                    logger.warning(
                        "github_export_reconciliation_failed",
                        (error as? AppError)?.userMessage ?? error.localizedDescription,
                        metadata: ["source_issue_id": issue.id.uuidString]
                    )
                }

                if error is AppError {
                    try? await receiptStore.clearReceipt(for: fingerprint)
                }
                let mappedError = OpenAIErrorMapper.mapTransportError(error, fallback: AppError.exportFailure)
                throw TrackerExportSupport.partialExportError(
                    mappedError,
                    providerName: "GitHub",
                    successfulCount: results.count
                )
            }
        }

        logger.info(
            "github_export_completed",
            "Finished exporting issues to GitHub.",
            metadata: [
                "issue_count": "\(results.count)",
                "repository": "\(configuration.owner)/\(configuration.repository)"
            ]
        )
        return results
    }

    func validate(configuration: GitHubExportConfiguration) async throws {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "GitHub export requires a personal access token, repository owner, and repository name."
            )
        }

        let request = try makeRepositoryValidationRequest(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("GitHub returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapGitHubError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let repository = try JSONDecoder().decode(GitHubRepositoryValidationResponse.self, from: data)
        guard repository.hasIssues else {
            throw AppError.exportFailure(
                "GitHub Issues are disabled for \(configuration.owner)/\(configuration.repository)."
            )
        }

        if let permissions = repository.permissions,
           !permissions.canCreateIssues {
            throw AppError.exportFailure(
                "The GitHub token can read \(configuration.owner)/\(configuration.repository), but it cannot create issues there."
            )
        }
    }

    func findOpenIssues(
        matching issue: ExtractedIssue,
        configuration: GitHubExportConfiguration
    ) async throws -> [TrackerIssueCandidate] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "GitHub export requires a personal access token, repository owner, and repository name."
            )
        }

        let request = try makeSearchRequest(issue: issue, configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("GitHub returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapGitHubError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let payload = try JSONDecoder().decode(GitHubSearchResponse.self, from: data)
        return payload.items.map { item in
            TrackerIssueCandidate(
                remoteIdentifier: "#\(item.number)",
                title: item.title,
                summary: item.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                remoteURL: item.htmlURL
            )
        }
    }

    func makeURLRequest(
        issue: ExtractedIssue,
        session reviewSession: TranscriptSession,
        configuration: GitHubExportConfiguration,
        exportFingerprint: String? = nil
    ) throws -> URLRequest {
        let endpoint = issueEndpoint(configuration: configuration)

        var request = authenticatedRequest(
            url: endpoint,
            httpMethod: "POST",
            token: configuration.token,
            includesJSONContentType: true
        )
        request.httpBody = try JSONEncoder().encode(
            GitHubIssueRequest(
                title: issue.title,
                body: try makeIssueBody(
                    issue: issue,
                    session: reviewSession,
                    exportFingerprint: exportFingerprint
                ),
                labels: configuration.labels.isEmpty ? nil : configuration.labels
            )
        )
        return request
    }

    private func makeRepositoryValidationRequest(
        configuration: GitHubExportConfiguration
    ) throws -> URLRequest {
        return authenticatedRequest(
            url: repositoryEndpoint(configuration: configuration),
            httpMethod: "GET",
            token: configuration.token,
            includesJSONContentType: false
        )
    }

    private func makeRepositoryListRequest(
        token: String,
        page: Int
    ) throws -> URLRequest {
        var components = URLComponents(string: "https://api.github.com/user/repos")!
        components.queryItems = [
            .init(name: "affiliation", value: "owner,collaborator,organization_member"),
            .init(name: "sort", value: "updated"),
            .init(name: "per_page", value: "100"),
            .init(name: "page", value: "\(page)")
        ]

        return authenticatedRequest(
            url: try url(from: components),
            httpMethod: "GET",
            token: token,
            includesJSONContentType: false
        )
    }

    private func makeSearchRequest(
        issue: ExtractedIssue,
        configuration: GitHubExportConfiguration
    ) throws -> URLRequest {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        let searchTerms = TrackerExportSupport.searchTerms(for: issue)
        let query = "repo:\(configuration.owner)/\(configuration.repository) is:issue is:open \(searchTerms)"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "5")
        ]

        return authenticatedRequest(
            url: try url(from: components),
            httpMethod: "GET",
            token: configuration.token,
            includesJSONContentType: false
        )
    }

    private func makeExportFingerprintSearchRequest(
        fingerprint: String,
        configuration: GitHubExportConfiguration
    ) throws -> URLRequest {
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        let query = #"repo:\#(configuration.owner)/\#(configuration.repository) is:issue "\#(TrackerExportFingerprint.marker(for: fingerprint))""#
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "per_page", value: "1")
        ]

        return authenticatedRequest(
            url: try url(from: components),
            httpMethod: "GET",
            token: configuration.token,
            includesJSONContentType: false
        )
    }

    /// Neutralizes untrusted (LLM-derived) text so it renders as literal content
    /// in a GitHub Markdown issue body: it cannot trigger `@mentions` or `#issue`
    /// cross-links, inject raw HTML, or start new block-level structure
    /// (headings, quotes, lists, tables, code fences).
    static func neutralizingUntrustedMarkdown(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            var escaped = line
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                // A zero-width space after @/# breaks GitHub's mention and issue
                // autolinks (and defeats `# heading` injection) while leaving the
                // text visually identical.
                .replacingOccurrences(of: "@", with: "@\u{200B}")
                .replacingOccurrences(of: "#", with: "#\u{200B}")
            if let first = escaped.first, "-*+|=`~".contains(first) {
                escaped = "\\" + escaped
            }
            return escaped
        }
        return lines.joined(separator: "\n")
    }

    private func makeIssueBody(
        issue: ExtractedIssue,
        session: TranscriptSession,
        exportFingerprint: String?
    ) throws -> String {
        var lines: [String] = [
            "## Summary",
            Self.neutralizingUntrustedMarkdown(
                TrackerExportPayloadBudget.truncated(
                    issue.summary,
                    maxCharacters: TrackerExportPayloadBudget.issueSummaryLimit
                )
            ),
            "",
            "## Evidence",
            Self.neutralizingUntrustedMarkdown(
                TrackerExportPayloadBudget.truncated(
                    issue.evidenceExcerpt,
                    maxCharacters: TrackerExportPayloadBudget.evidenceLimit
                )
            ),
            ""
        ]

        if let timestampLabel = issue.timestampLabel {
            lines.append("- Transcript time: `\(timestampLabel)`")
        }

        lines.append("- Severity: \(issue.severity.rawValue)")

        if let component = issue.component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            lines.append("- Component: \(Self.neutralizingUntrustedMarkdown(component))")
        }

        lines.append("- Deduplication hint: `\(issue.deduplicationHint)`")

        if let sectionTitle = issue.sectionTitle, !sectionTitle.isEmpty {
            lines.append("- Transcript section: \(Self.neutralizingUntrustedMarkdown(sectionTitle))")
        }

        if let confidenceLabel = issue.confidenceLabel {
            lines.append("- Confidence: \(confidenceLabel)")
        }

        if issue.requiresReview {
            lines.append("- Review needed: Yes")
        }

        if let note = issue.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            lines.append("")
            // `note` is set by our own dedup policy (trackerContextNote) and may
            // deliberately contain a "Related to #123" cross-link, so it is not
            // neutralized here.
            lines.append("## Tracker Context")
            lines.append(
                TrackerExportPayloadBudget.truncated(
                    note,
                    maxCharacters: TrackerExportPayloadBudget.noteLimit
                )
            )
        }

        if !issue.reproductionSteps.isEmpty {
            lines.append("")
            lines.append("## Reproduction Steps")

            for (index, step) in issue.reproductionSteps.prefix(TrackerExportPayloadBudget.reproductionStepLimit).enumerated() {
                lines.append(
                    "\(index + 1). \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(step.instruction, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))"
                )

                if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !expectedResult.isEmpty {
                    lines.append("   - Expected: \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(expectedResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
                }

                if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !actualResult.isEmpty {
                    lines.append("   - Actual: \(Self.neutralizingUntrustedMarkdown(TrackerExportPayloadBudget.truncated(actualResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
                }

                if let reference = reproductionStepReference(step, session: session) {
                    lines.append("   - Reference: \(reference)")
                }
            }
        }

        let annotationLines = try annotatedScreenshotLines(issue: issue, session: session)
        if !annotationLines.isEmpty {
            lines.append("")
            lines.append("## Annotated Screenshots")
            lines.append(
                contentsOf: TrackerExportPayloadBudget.limitedList(
                    annotationLines,
                    maxItems: TrackerExportPayloadBudget.screenshotListLimit,
                    maxCharactersPerItem: TrackerExportPayloadBudget.listEntryLimit
                )
            )
        }

        let screenshots = session.screenshots(for: issue)
        if !screenshots.isEmpty {
            lines.append("")
            lines.append("## Related Screenshots")
            for screenshot in screenshots.prefix(TrackerExportPayloadBudget.screenshotListLimit) {
                lines.append("- \(screenshot.fileName) (`\(screenshot.timeLabel)`) - attach manually from the exported session bundle if needed.")
            }
        }

        lines.append("")
        lines.append("## Source")
        lines.append("Exported from BugNarrator. Review against the raw transcript before triage.")

        let footer = exportFingerprint.map { "\n\n\(TrackerExportFingerprint.marker(for: $0))" } ?? ""
        return TrackerExportPayloadBudget.hardLimitMarkdown(
            lines.joined(separator: "\n"),
            maxCharacters: TrackerExportPayloadBudget.gitHubBodyLimit - footer.count
        ) + footer
    }

    private func existingExportResult(
        fingerprint: String,
        sourceIssueID: UUID,
        configuration: GitHubExportConfiguration
    ) async throws -> ExportResult? {
        if let receipt = try await receiptStore.receipt(for: fingerprint),
           let exportResult = receipt.asExportResult() {
            return exportResult
        }

        guard try await receiptStore.receipt(for: fingerprint)?.state == .pending else {
            return nil
        }

        return try await reconcilePendingExport(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            configuration: configuration
        )
    }

    private func reconcilePendingExport(
        fingerprint: String,
        sourceIssueID: UUID,
        configuration: GitHubExportConfiguration
    ) async throws -> ExportResult? {
        guard let candidate = try await findExportedIssue(
            fingerprint: fingerprint,
            configuration: configuration
        ) else {
            return nil
        }

        try await receiptStore.markSucceeded(
            fingerprint: fingerprint,
            sourceIssueID: sourceIssueID,
            destination: .github,
            targetIdentity: configuration.targetIdentity,
            remoteIdentifier: candidate.remoteIdentifier,
            remoteURL: candidate.remoteURL
        )

        return ExportResult(
            sourceIssueID: sourceIssueID,
            destination: .github,
            remoteIdentifier: candidate.remoteIdentifier,
            remoteURL: candidate.remoteURL
        )
    }

    private func findExportedIssue(
        fingerprint: String,
        configuration: GitHubExportConfiguration
    ) async throws -> TrackerIssueCandidate? {
        let request = try makeExportFingerprintSearchRequest(
            fingerprint: fingerprint,
            configuration: configuration
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("GitHub returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapGitHubError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let payload = try JSONDecoder().decode(GitHubSearchResponse.self, from: data)
        guard let item = payload.items.first else {
            return nil
        }

        return TrackerIssueCandidate(
            remoteIdentifier: "#\(item.number)",
            title: item.title,
            summary: item.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            remoteURL: item.htmlURL
        )
    }

    private func reproductionStepReference(_ step: IssueReproductionStep, session: TranscriptSession) -> String? {
        var parts: [String] = []

        if let timestampLabel = step.timestampLabel {
            parts.append("Transcript `\(timestampLabel)`")
        }

        if let screenshotID = step.screenshotID,
           let screenshot = session.screenshot(with: screenshotID) {
            parts.append("Screenshot `\(screenshot.fileName)` (`\(screenshot.timeLabel)`)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  •  ")
    }

    private func annotatedScreenshotLines(issue: ExtractedIssue, session: TranscriptSession) throws -> [String] {
        try annotationRenderer.annotatedScreenshotExports(for: issue, session: session).map { export in
            if let renderedFileName = export.renderedFileName {
                return "- \(renderedFileName) from `\(export.screenshotFileName)` (`\(export.timeLabel)`) — \(export.summaries)"
            }

            return "- \(export.screenshotFileName) (`\(export.timeLabel)`) — \(export.summaries)"
        }
    }

    private func mapGitHubError(
        statusCode: Int,
        data: Data,
        configuration: GitHubExportConfiguration,
        retryAfterSeconds: Int? = nil
    ) -> AppError {
        let message = decodeGitHubMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let normalizedMessage = message.lowercased()

        // A secondary rate limit returns 429 (not 401/403); map it explicitly so
        // the user gets a "wait and retry" message rather than a token/auth error.
        if statusCode == 429 || normalizedMessage.contains("rate limit") {
            return .exportFailure("GitHub rate limited the request.\(TrackerExportSupport.retryAfterSuffix(retryAfterSeconds))")
        }

        if statusCode == 401 || statusCode == 403 {
            return .exportFailure("GitHub rejected the token or repository access for \(configuration.owner)/\(configuration.repository).")
        }

        if statusCode == 404 {
            return .exportFailure("GitHub could not find \(configuration.owner)/\(configuration.repository). Check the owner, repository name, and token permissions.")
        }

        if statusCode == 422 {
            return .exportFailure("GitHub rejected the issue payload: \(message)")
        }

        return .exportFailure("GitHub returned \(statusCode): \(message)")
    }

    private func decodeGitHubMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(GitHubErrorResponse.self, from: data))?.message
    }

    private func url(from components: URLComponents) throws -> URL {
        guard let url = components.url else {
            throw AppError.exportFailure("GitHub search query could not be constructed.")
        }

        return url
    }

    /// Produces a GitHub REST request with the shared Bearer auth, Accept, and
    /// User-Agent headers applied. Pass `includesJSONContentType` for requests
    /// that carry a JSON body.
    private func authenticatedRequest(
        url: URL,
        httpMethod: String,
        token: String,
        includesJSONContentType: Bool
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        if includesJSONContentType {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func repositoryEndpoint(configuration: GitHubExportConfiguration) -> URL {
        let owner = configuration.owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.owner
        let repository = configuration.repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.repository
        return URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!
    }

    private func issueEndpoint(configuration: GitHubExportConfiguration) -> URL {
        repositoryEndpoint(configuration: configuration).appendingPathComponent("issues")
    }
}

private struct GitHubIssueRequest: Encodable {
    let title: String
    let body: String
    let labels: [String]?
}

private struct GitHubIssueResponse: Decodable {
    let number: Int
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

private struct GitHubRepositoryValidationResponse: Decodable {
    let nodeID: String?
    let name: String?
    let owner: GitHubRepositoryOwner?
    let hasIssues: Bool
    let permissions: GitHubRepositoryPermissions?

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case name
        case owner
        case hasIssues = "has_issues"
        case permissions
    }
}

private struct GitHubRepositoryListItem: Decodable {
    let nodeID: String?
    let name: String
    let description: String?
    let hasIssues: Bool
    let permissions: GitHubRepositoryPermissions?
    let owner: GitHubRepositoryOwner

    enum CodingKeys: String, CodingKey {
        case nodeID = "node_id"
        case name
        case description
        case hasIssues = "has_issues"
        case permissions
        case owner
    }
}

private struct GitHubRepositoryOwner: Decodable {
    let login: String
}

private struct GitHubRepositoryPermissions: Decodable {
    let admin: Bool?
    let maintain: Bool?
    let push: Bool?
    let triage: Bool?

    var canCreateIssues: Bool {
        admin == true || maintain == true || push == true || triage == true
    }
}

private struct GitHubSearchResponse: Decodable {
    let items: [GitHubSearchItem]
}

private struct GitHubSearchItem: Decodable {
    let number: Int
    let title: String
    let body: String?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case body
        case htmlURL = "html_url"
    }
}

private struct GitHubErrorResponse: Decodable {
    let message: String
}
