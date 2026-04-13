import Foundation

actor JiraExportProvider {
    private let session: URLSession
    private let logger = DiagnosticsLogger(category: .export)
    private let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
    }

    func export(
        issues: [ExtractedIssue],
        session reviewSession: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira export requires a base URL, email, API token, project key, and issue type."
            )
        }

        logger.info(
            "jira_export_requested",
            "Exporting selected issues to Jira.",
            metadata: [
                "issue_count": "\(issues.count)",
                "project_key": configuration.projectKey,
                "session_id": reviewSession.id.uuidString
            ]
        )

        var results: [ExportResult] = []

        for issue in issues {
            let request = try makeURLRequest(issue: issue, session: reviewSession, configuration: configuration)

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.exportFailure("Jira returned an invalid response.")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw mapJiraError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
                }

                let payload = try JSONDecoder().decode(JiraIssueResponse.self, from: data)
                results.append(
                    ExportResult(
                        sourceIssueID: issue.id,
                        destination: .jira,
                        remoteIdentifier: payload.key,
                        remoteURL: configuration.baseURL.appending(path: "browse/\(payload.key)")
                    )
                )
                logger.info(
                    "jira_issue_exported",
                    "Exported one issue to Jira.",
                    metadata: [
                        "source_issue_id": issue.id.uuidString,
                        "remote_identifier": payload.key
                    ]
                )
            } catch {
                logger.error(
                    "jira_export_failed",
                    (error as? AppError)?.userMessage ?? error.localizedDescription,
                    metadata: [
                        "successful_count": "\(results.count)",
                        "source_issue_id": issue.id.uuidString
                    ]
                )
                let mappedError = OpenAIErrorMapper.mapTransportError(error, fallback: AppError.exportFailure)
                throw partialExportError(mappedError, successfulCount: results.count)
            }
        }

        logger.info(
            "jira_export_completed",
            "Finished exporting issues to Jira.",
            metadata: [
                "issue_count": "\(results.count)",
                "project_key": configuration.projectKey
            ]
        )
        return results
    }

    func findOpenIssues(
        matching issue: ExtractedIssue,
        configuration: JiraExportConfiguration
    ) async throws -> [TrackerIssueCandidate] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira export requires a base URL, email, API token, project key, and issue type."
            )
        }

        let request = try makeSearchRequest(issue: issue, configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let payload = try JSONDecoder().decode(JiraSearchResponse.self, from: data)
        return payload.issues.map { issue in
            TrackerIssueCandidate(
                remoteIdentifier: issue.key,
                title: issue.fields.summary,
                summary: issue.fields.description?.plainText ?? "",
                remoteURL: configuration.baseURL.appending(path: "browse/\(issue.key)")
            )
        }
    }

    func makeURLRequest(
        issue: ExtractedIssue,
        session reviewSession: TranscriptSession,
        configuration: JiraExportConfiguration
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/issue")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Basic \(basicAuthValue(email: configuration.email, apiToken: configuration.apiToken))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            JiraIssueRequest(
                fields: .init(
                    project: .init(key: configuration.projectKey),
                    summary: issue.title,
                    issueType: .init(name: configuration.issueType),
                    description: try makeDescription(issue: issue, session: reviewSession)
                )
            )
        )
        return request
    }

    private func makeSearchRequest(
        issue: ExtractedIssue,
        configuration: JiraExportConfiguration
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/search/jql")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(
            "Basic \(basicAuthValue(email: configuration.email, apiToken: configuration.apiToken))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            JiraSearchRequest(
                jql: searchJQL(for: issue, projectKey: configuration.projectKey),
                maxResults: 5,
                fields: ["summary", "description"]
            )
        )
        return request
    }

    private func basicAuthValue(email: String, apiToken: String) -> String {
        let rawValue = "\(email):\(apiToken)"
        return Data(rawValue.utf8).base64EncodedString()
    }

    private func makeDescription(issue: ExtractedIssue, session: TranscriptSession) throws -> JiraDocument {
        var content: [JiraBlock] = [
            .paragraph(text: "Summary: \(issue.summary)"),
            .paragraph(text: "Evidence: \(issue.evidenceExcerpt)")
        ]

        var metadataLines: [String] = []
        if let timestampLabel = issue.timestampLabel {
            metadataLines.append("Transcript time: \(timestampLabel)")
        }
        metadataLines.append("Severity: \(issue.severity.rawValue)")
        if let component = issue.component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            metadataLines.append("Component: \(component)")
        }
        metadataLines.append("Deduplication hint: \(issue.deduplicationHint)")
        if let sectionTitle = issue.sectionTitle, !sectionTitle.isEmpty {
            metadataLines.append("Transcript section: \(sectionTitle)")
        }
        if let confidenceLabel = issue.confidenceLabel {
            metadataLines.append("Confidence: \(confidenceLabel)")
        }
        if issue.requiresReview {
            metadataLines.append("Review needed: Yes")
        }

        if !metadataLines.isEmpty {
            content.append(.bulletList(items: metadataLines))
        }

        if let note = issue.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            content.append(.paragraph(text: "Tracker context: \(note)"))
        }

        if !issue.reproductionSteps.isEmpty {
            let stepLines = issue.reproductionSteps.enumerated().map { index, step in
                formattedReproductionStep(step, index: index, session: session)
            }
            content.append(.paragraph(text: "Reproduction steps"))
            content.append(.bulletList(items: stepLines))
        }

        let annotationLines = try annotatedScreenshotLines(issue: issue, session: session)
        if !annotationLines.isEmpty {
            content.append(.paragraph(text: "Annotated screenshots"))
            content.append(.bulletList(items: annotationLines))
        }

        let screenshots = session.screenshots(for: issue)
        if !screenshots.isEmpty {
            let screenshotLines = screenshots.map {
                "\($0.fileName) (\($0.timeLabel)) - attach manually from the exported session bundle if needed."
            }
            content.append(.paragraph(text: "Related screenshots"))
            content.append(.bulletList(items: screenshotLines))
        }

        content.append(.paragraph(text: "Exported from BugNarrator. Review against the raw transcript before triage."))
        return JiraDocument(content: content)
    }

    private func formattedReproductionStep(
        _ step: IssueReproductionStep,
        index: Int,
        session: TranscriptSession
    ) -> String {
        var parts = ["\(index + 1). \(step.instruction)"]

        if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedResult.isEmpty {
            parts.append("Expected: \(expectedResult)")
        }

        if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actualResult.isEmpty {
            parts.append("Actual: \(actualResult)")
        }

        var references: [String] = []
        if let timestampLabel = step.timestampLabel {
            references.append("Transcript \(timestampLabel)")
        }
        if let screenshotID = step.screenshotID,
           let screenshot = session.screenshot(with: screenshotID) {
            references.append("Screenshot \(screenshot.fileName) (\(screenshot.timeLabel))")
        }

        if !references.isEmpty {
            parts.append("Reference: \(references.joined(separator: " • "))")
        }

        return parts.joined(separator: " | ")
    }

    private func annotatedScreenshotLines(issue: ExtractedIssue, session: TranscriptSession) throws -> [String] {
        let screenshots = session.screenshots(for: issue).filter {
            !issue.screenshotAnnotations(for: $0.id).isEmpty
        }

        guard !screenshots.isEmpty else {
            return []
        }

        let annotationDirectoryURL = session.artifactsDirectoryURL?.appendingPathComponent(
            "annotated-exports",
            isDirectory: true
        )

        return try screenshots.map { screenshot in
            let renderedAsset = try annotationDirectoryURL.flatMap {
                try annotationRenderer.writeAnnotatedScreenshot(
                    for: issue,
                    screenshot: screenshot,
                    to: $0
                )
            }
            let summaries = issue.screenshotAnnotations(for: screenshot.id).map(\.exportDescription).joined(separator: "; ")

            if let renderedAsset {
                return "\(renderedAsset.fileName) from \(screenshot.fileName) (\(screenshot.timeLabel)) - \(summaries)"
            }

            return "\(screenshot.fileName) (\(screenshot.timeLabel)) - \(summaries)"
        }
    }

    private func mapJiraError(
        statusCode: Int,
        data: Data,
        configuration: JiraExportConfiguration
    ) -> AppError {
        let message = decodeJiraMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let normalizedMessage = message.lowercased()

        if statusCode == 401 || statusCode == 403 {
            if normalizedMessage.contains("rate limit") {
                return .exportFailure("Jira rate limited the request. Wait a moment and try again.")
            }

            return .exportFailure("Jira rejected the credentials for project \(configuration.projectKey).")
        }

        if statusCode == 404 {
            return .exportFailure("Jira could not find the configured site or project \(configuration.projectKey).")
        }

        if statusCode == 400 {
            return .exportFailure("Jira rejected the issue payload: \(message)")
        }

        return .exportFailure("Jira returned \(statusCode): \(message)")
    }

    private func decodeJiraMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(JiraErrorResponse.self, from: data) {
            let messages = payload.errorMessages + payload.errors.values
            return messages.joined(separator: " ")
        }

        return nil
    }

    private func partialExportError(_ error: AppError, successfulCount: Int) -> AppError {
        guard successfulCount > 0 else {
            return error
        }

        return .exportFailure(
            "Jira exported \(successfulCount) issue\(successfulCount == 1 ? "" : "s") before failing. \(error.userMessage)"
        )
    }

    private func searchJQL(for issue: ExtractedIssue, projectKey: String) -> String {
        let phrase = searchPhrase(for: issue)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        project = \(projectKey) AND statusCategory != Done AND (summary ~ "\\"\(phrase)\\"" OR description ~ "\\"\(phrase)\\"") ORDER BY updated DESC
        """
    }

    private func searchPhrase(for issue: ExtractedIssue) -> String {
        let source = [issue.title, issue.component, issue.summary]
            .compactMap { $0 }
            .joined(separator: " ")
        let significantTerms = source
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }

        return significantTerms.prefix(6).joined(separator: " ")
    }
}

private struct JiraIssueRequest: Encodable {
    let fields: JiraIssueFields
}

private struct JiraIssueFields: Encodable {
    let project: JiraProjectField
    let summary: String
    let issueType: JiraIssueTypeField
    let description: JiraDocument

    enum CodingKeys: String, CodingKey {
        case project
        case summary
        case issueType = "issuetype"
        case description
    }
}

private struct JiraProjectField: Encodable {
    let key: String
}

private struct JiraIssueTypeField: Encodable {
    let name: String
}

private struct JiraDocument: Encodable {
    let type = "doc"
    let version = 1
    let content: [JiraBlock]
}

private struct JiraBlock: Encodable {
    let type: String
    let content: [JiraInline]?

    static func paragraph(text: String) -> JiraBlock {
        JiraBlock(type: "paragraph", content: [.text(text)])
    }

    static func bulletList(items: [String]) -> JiraBlock {
        JiraBlock(
            type: "bulletList",
            content: items.map { item in
                JiraInline.listItem(
                    JiraBlock(type: "paragraph", content: [.text(item)])
                )
            }
        )
    }
}

private struct JiraInline: Encodable {
    let type: String
    let text: String?
    let content: [JiraBlock]?

    static func text(_ value: String) -> JiraInline {
        JiraInline(type: "text", text: value, content: nil)
    }

    static func listItem(_ block: JiraBlock) -> JiraInline {
        JiraInline(type: "listItem", text: nil, content: [block])
    }
}

private struct JiraIssueResponse: Decodable {
    let id: String
    let key: String
}

private struct JiraSearchRequest: Encodable {
    let jql: String
    let maxResults: Int
    let fields: [String]

    enum CodingKeys: String, CodingKey {
        case jql
        case maxResults = "maxResults"
        case fields
    }
}

private struct JiraSearchResponse: Decodable {
    let issues: [JiraSearchIssue]
}

private struct JiraSearchIssue: Decodable {
    let key: String
    let fields: JiraSearchIssueFields
}

private struct JiraSearchIssueFields: Decodable {
    let summary: String
    let description: JiraADFNode?
}

private struct JiraADFNode: Decodable {
    let type: String?
    let text: String?
    let content: [JiraADFNode]?

    var plainText: String {
        let childText = content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if childText.isEmpty {
                return text
            }

            return [text, childText].joined(separator: " ")
        }

        return childText
    }
}

private struct JiraErrorResponse: Decodable {
    let errorMessages: [String]
    let errors: [String: String]
}
