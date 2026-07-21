import Foundation

actor JiraExportProvider {
    private let session: URLSession
    private let receiptStore: any ExportReceiptStoring
    private let retryConfiguration: ExportRetryConfiguration
    private let logger = DiagnosticsLogger(category: .export)
    private let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(
        session: URLSession? = nil,
        receiptStore: any ExportReceiptStoring = ExportReceiptStore(),
        retryConfiguration: ExportRetryConfiguration = .default
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
        self.retryConfiguration = retryConfiguration
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
            let fingerprint = TrackerExportFingerprint.make(
                destination: .jira,
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
                destination: .jira,
                targetIdentity: configuration.targetIdentity
            )

            let request = try makeURLRequest(
                issue: issue,
                session: reviewSession,
                configuration: configuration,
                exportFingerprint: fingerprint
            )

            let result = try await createWithRetry(
                issue: issue,
                fingerprint: fingerprint,
                request: request,
                configuration: configuration,
                successfulCount: results.count
            )
            results.append(result)
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

    func validate(configuration: JiraExportConfiguration) async throws {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira export requires a base URL, email, API token, project key, and issue type."
            )
        }

        let issueTypes = try await fetchIssueTypes(
            for: configuration.projectKey,
            projectID: configuration.projectID,
            configuration: JiraConnectionConfiguration(
                baseURL: configuration.baseURL,
                email: configuration.email,
                apiToken: configuration.apiToken
            )
        )

        guard let issueType = issueTypes.first(where: {
            $0.id == configuration.issueTypeID
                || $0.name.compare(configuration.issueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else {
            throw AppError.exportFailure(
                "Jira project \(configuration.projectKey) does not expose issue type \(configuration.issueTypeName)."
            )
        }

        let requiredFields = try await fetchRequiredCreateFields(
            for: configuration.projectKey,
            issueTypeID: issueType.id,
            configuration: JiraConnectionConfiguration(
                baseURL: configuration.baseURL,
                email: configuration.email,
                apiToken: configuration.apiToken
            )
        )

        let unsupportedRequiredFields = requiredFields.filter {
            !$0.isSystemFieldSupportedByBugNarrator
        }

        if !unsupportedRequiredFields.isEmpty {
            let fieldList = unsupportedRequiredFields.map(\.displayName).joined(separator: ", ")
            throw AppError.exportFailure(
                "Jira requires additional fields before BugNarrator can create issues in \(configuration.projectKey): \(fieldList)."
            )
        }
    }

    func fetchProjects(
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira project discovery requires a base URL, email, and API token."
            )
        }

        var startAt = 0
        var projects: [JiraProjectOption] = []

        while true {
            let request = try makeProjectSearchRequest(configuration: configuration, startAt: startAt)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.exportFailure("Jira returned an invalid response.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw mapJiraError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    configuration: JiraExportConfiguration(
                        baseURL: configuration.baseURL,
                        email: configuration.email,
                        apiToken: configuration.apiToken,
                        projectKey: "",
                        issueType: ""
                    )
                )
            }

            let payload = try decodeJiraPayload(
                JiraCreateMetadataProjectsResponse.self,
                from: data,
                description: "project metadata"
            )
            projects.append(
                contentsOf: payload.projects.compactMap(\.option)
            )

            let nextStartAt = startAt + (payload.maxResults ?? payload.projects.count)
            if payload.projects.isEmpty || nextStartAt <= startAt || nextStartAt >= payload.total {
                break
            }

            startAt = nextStartAt
        }

        return projects.sorted {
            if $0.key.caseInsensitiveCompare($1.key) == .orderedSame {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }
    }

    func fetchIssueTypes(
        for projectKey: String,
        projectID: String? = nil,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        guard configuration.isComplete, !projectKey.isEmpty else {
            throw AppError.exportConfigurationMissing(
                "Jira issue type discovery requires a base URL, email, API token, and project key."
            )
        }

        let payload = try await fetchCreateIssueTypesPayload(
            for: projectKey,
            projectID: projectID,
            configuration: configuration
        )
        var seenNames = Set<String>()
        return payload.issueTypes.compactMap { issueType in
            guard let option = issueType.option else {
                return nil
            }

            let key = option.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenNames.insert(key).inserted else {
                return nil
            }

            return option
        }
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
        configuration: JiraExportConfiguration,
        exportFingerprint: String? = nil
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/issue")
        var request = authenticatedRequest(
            url: endpoint,
            httpMethod: "POST",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: true
        )
        request.httpBody = try JSONEncoder().encode(
            JiraIssueRequest(
                fields: .init(
                    project: .init(key: configuration.projectKey),
                    summary: issue.title,
                    issueType: .init(id: configuration.issueTypeID, name: configuration.issueTypeName),
                    description: try makeDescription(
                        issue: issue,
                        session: reviewSession,
                        exportFingerprint: exportFingerprint
                    )
                )
            )
        )
        return request
    }

    private func makeProjectSearchRequest(
        configuration: JiraConnectionConfiguration,
        startAt: Int
    ) throws -> URLRequest {
        let url = try jiraRequestURL(
            baseURL: configuration.baseURL,
            path: "rest/api/3/project/search",
            queryItems: [
                .init(name: "startAt", value: "\(startAt)"),
                .init(name: "maxResults", value: "50")
            ]
        )

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func makeProjectIssueTypesRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String,
        projectID: String?
    ) throws -> URLRequest {
        let url: URL
        if let normalizedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            url = try jiraRequestURL(
                baseURL: configuration.baseURL,
                path: "rest/api/3/issuetype/project",
                queryItems: [.init(name: "projectId", value: normalizedProjectID)]
            )
        } else {
            url = configuration.baseURL.appending(path: "rest/api/3/project/\(projectKey)")
        }

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func makeCreateFieldMetadataRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String,
        issueTypeID: String
    ) throws -> URLRequest {
        let url = try jiraRequestURL(
            baseURL: configuration.baseURL,
            path: "rest/api/3/issue/createmeta/\(projectKey)/issuetypes/\(issueTypeID)",
            queryItems: [
                .init(name: "startAt", value: "0"),
                .init(name: "maxResults", value: "100")
            ]
        )

        return authenticatedRequest(
            url: url,
            httpMethod: "GET",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: false
        )
    }

    private func fetchCreateIssueTypesPayload(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> JiraCreateMetaIssueTypesResponse {
        let request = try makeProjectIssueTypesRequest(
            configuration: configuration,
            projectKey: projectKey,
            projectID: projectID
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(
                statusCode: httpResponse.statusCode,
                data: data,
                configuration: JiraExportConfiguration(
                    baseURL: configuration.baseURL,
                    email: configuration.email,
                    apiToken: configuration.apiToken,
                    projectKey: projectKey,
                    issueType: ""
                )
            )
        }

        return try decodeJiraPayload(
            JiraCreateMetaIssueTypesResponse.self,
            from: data,
            description: "issue type metadata"
        )
    }

    private func fetchRequiredCreateFields(
        for projectKey: String,
        issueTypeID: String,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraCreateFieldMetadata] {
        let request = try makeCreateFieldMetadataRequest(
            configuration: configuration,
            projectKey: projectKey,
            issueTypeID: issueTypeID
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(
                statusCode: httpResponse.statusCode,
                data: data,
                configuration: JiraExportConfiguration(
                    baseURL: configuration.baseURL,
                    email: configuration.email,
                    apiToken: configuration.apiToken,
                    projectKey: projectKey,
                    issueType: issueTypeID
                )
            )
        }

        let payload = try decodeJiraPayload(
            JiraCreateFieldMetadataResponse.self,
            from: data,
            description: "field metadata"
        )
        return payload.fields.filter(\.required)
    }



    private func makeSearchRequest(
        issue: ExtractedIssue,
        configuration: JiraExportConfiguration
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/search/jql")
        var request = authenticatedRequest(
            url: endpoint,
            httpMethod: "POST",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: true
        )
        request.httpBody = try JSONEncoder().encode(
            JiraSearchRequest(
                jql: searchJQL(for: issue, projectKey: configuration.projectKey),
                maxResults: 5,
                fields: ["summary", "description"]
            )
        )
        return request
    }

    private func makeExportFingerprintSearchRequest(
        fingerprint: String,
        configuration: JiraExportConfiguration
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/search/jql")
        var request = authenticatedRequest(
            url: endpoint,
            httpMethod: "POST",
            email: configuration.email,
            apiToken: configuration.apiToken,
            includesJSONContentType: true
        )
        request.httpBody = try JSONEncoder().encode(
            JiraSearchRequest(
                jql: #"\#(Self.jqlProjectClause(configuration.projectKey)) AND description ~ "\"\#(TrackerExportFingerprint.marker(for: fingerprint))\"" ORDER BY created DESC"#,
                maxResults: 1,
                fields: ["summary", "description"]
            )
        )
        return request
    }




    /// Creates one issue with bounded retry. Transient failures (network / 5xx /
    /// 429) are retried with backoff, but only after a marker reconciliation
    /// confirms the issue was not already created — so a created-but-unacked issue
    /// is never duplicated. The pending receipt is kept across transient retries;
    /// cleared only on a confirmed permanent failure.
    private static let retryContext = TrackerExportRetryContext(
        displayName: "Jira",
        destination: .jira,
        exportedLogEvent: "jira_issue_exported",
        failedLogEvent: "jira_export_failed",
        reconciliationFailedLogEvent: "jira_export_reconciliation_failed"
    )

    private func createWithRetry(
        issue: ExtractedIssue,
        fingerprint: String,
        request: URLRequest,
        configuration: JiraExportConfiguration,
        successfulCount: Int
    ) async throws -> ExportResult {
        try await TrackerExportSupport.runCreateWithRetry(
            issueID: issue.id,
            fingerprint: fingerprint,
            targetIdentity: configuration.targetIdentity,
            successfulCount: successfulCount,
            configuration: retryConfiguration,
            receiptStore: receiptStore,
            logger: logger,
            context: Self.retryContext,
            attemptCreate: { await self.attemptCreate(request, configuration: configuration) },
            reconcile: {
                try await self.reconcilePendingExport(
                    fingerprint: fingerprint,
                    sourceIssueID: issue.id,
                    configuration: configuration
                )
            }
        )
    }

    private func attemptCreate(
        _ request: URLRequest,
        configuration: JiraExportConfiguration
    ) async -> ExportCreateOutcome {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .permanent(.exportFailure("Jira returned an invalid response."))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let retryAfter = TrackerExportSupport.retryAfterSeconds(from: httpResponse)
                let mapped = mapJiraError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    configuration: configuration,
                    retryAfterSeconds: retryAfter
                )
                return TrackerExportSupport.isTransientStatus(httpResponse.statusCode)
                    ? .transient(mapped, retryAfterSeconds: retryAfter)
                    : .permanent(mapped)
            }

            do {
                let payload = try JSONDecoder().decode(JiraIssueResponse.self, from: data)
                let remoteURL = configuration.baseURL.appending(path: "browse/\(payload.key)")
                return .success(remoteIdentifier: payload.key, remoteURL: remoteURL)
            } catch {
                // A 2xx whose body we cannot read is a created-but-unacknowledged
                // issue: Jira accepted the create, but we could not parse the key.
                // Treat it as ambiguous/transient — NOT permanent — so the pending
                // receipt is preserved and reconciliation-by-marker resolves it,
                // instead of clearing the receipt and risking a duplicate on a
                // later export.
                return .transient(.exportFailure("Jira returned an unreadable response."), retryAfterSeconds: nil)
            }
        } catch {
            let mapped = OpenAIErrorMapper.mapTransportError(error, fallback: AppError.exportFailure)
            return .transient(mapped, retryAfterSeconds: nil)
        }
    }

    private func existingExportResult(
        fingerprint: String,
        sourceIssueID: UUID,
        configuration: JiraExportConfiguration
    ) async throws -> ExportResult? {
        if let receipt = try await receiptStore.receipt(for: fingerprint),
           let exportResult = receipt.asExportResult() {
            return exportResult
        }

        guard let receipt = try await receiptStore.receipt(for: fingerprint),
              receipt.state == .pending else {
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
        configuration: JiraExportConfiguration
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
            destination: .jira,
            targetIdentity: configuration.targetIdentity,
            remoteIdentifier: candidate.remoteIdentifier,
            remoteURL: candidate.remoteURL
        )

        return ExportResult(
            sourceIssueID: sourceIssueID,
            destination: .jira,
            remoteIdentifier: candidate.remoteIdentifier,
            remoteURL: candidate.remoteURL
        )
    }

    private func findExportedIssue(
        fingerprint: String,
        configuration: JiraExportConfiguration
    ) async throws -> TrackerIssueCandidate? {
        let request = try makeExportFingerprintSearchRequest(
            fingerprint: fingerprint,
            configuration: configuration
        )
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("Jira returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapJiraError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let payload = try JSONDecoder().decode(JiraSearchResponse.self, from: data)
        guard let issue = payload.issues.first else {
            return nil
        }

        return TrackerIssueCandidate(
            remoteIdentifier: issue.key,
            title: issue.fields.summary,
            summary: issue.fields.description?.plainText ?? "",
            remoteURL: configuration.baseURL.appending(path: "browse/\(issue.key)")
        )
    }

    private func makeDescription(
        issue: ExtractedIssue,
        session: TranscriptSession,
        exportFingerprint: String?
    ) throws -> JiraDocument {
        var content: [JiraBlock] = [
            .paragraph(
                text: "Summary: \(TrackerExportPayloadBudget.truncated(issue.summary, maxCharacters: TrackerExportPayloadBudget.issueSummaryLimit))"
            ),
            .paragraph(
                text: "Evidence: \(TrackerExportPayloadBudget.truncated(issue.evidenceExcerpt, maxCharacters: TrackerExportPayloadBudget.evidenceLimit))"
            )
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
            content.append(
                .bulletList(
                    items: TrackerExportPayloadBudget.limitedList(
                        metadataLines,
                        maxItems: TrackerExportPayloadBudget.metadataItemLimit,
                        maxCharactersPerItem: TrackerExportPayloadBudget.listEntryLimit
                    )
                )
            )
        }

        if let note = issue.note?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            content.append(
                .paragraph(
                    text: "Tracker context: \(TrackerExportPayloadBudget.truncated(note, maxCharacters: TrackerExportPayloadBudget.noteLimit))"
                )
            )
        }

        if !issue.reproductionSteps.isEmpty {
            let stepLines = issue.reproductionSteps.prefix(TrackerExportPayloadBudget.reproductionStepLimit).enumerated().map { index, step in
                formattedReproductionStep(step, index: index, session: session)
            }
            content.append(.paragraph(text: "Reproduction steps"))
            content.append(
                .bulletList(
                    items: TrackerExportPayloadBudget.limitedList(
                        stepLines,
                        maxItems: TrackerExportPayloadBudget.reproductionStepLimit,
                        maxCharactersPerItem: TrackerExportPayloadBudget.listEntryLimit
                    )
                )
            )
        }

        let annotationLines = try annotatedScreenshotLines(issue: issue, session: session)
        if !annotationLines.isEmpty {
            content.append(.paragraph(text: "Annotated screenshots"))
            content.append(
                .bulletList(
                    items: TrackerExportPayloadBudget.limitedList(
                        annotationLines,
                        maxItems: TrackerExportPayloadBudget.screenshotListLimit,
                        maxCharactersPerItem: TrackerExportPayloadBudget.listEntryLimit
                    )
                )
            )
        }

        let screenshots = session.screenshots(for: issue)
        if !screenshots.isEmpty {
            let screenshotLines = screenshots.prefix(TrackerExportPayloadBudget.screenshotListLimit).map {
                "\($0.fileName) (\($0.timeLabel)) - attach manually from the exported session bundle if needed."
            }
            content.append(.paragraph(text: "Related screenshots"))
            content.append(.bulletList(items: screenshotLines))
        }

        content.append(.paragraph(text: "Exported from BugNarrator. Review against the raw transcript before triage."))
        let footer = exportFingerprint.map { JiraBlock.paragraph(text: TrackerExportFingerprint.marker(for: $0)) }

        var limitedContent = hardLimit(
            content,
            maxCharacters: TrackerExportPayloadBudget.jiraTextLimit - (footer?.plainText.count ?? 0)
        )
        if let footer {
            limitedContent.append(footer)
        }

        return JiraDocument(content: limitedContent)
    }

    private func formattedReproductionStep(
        _ step: IssueReproductionStep,
        index: Int,
        session: TranscriptSession
    ) -> String {
        var parts = ["\(index + 1). \(TrackerExportPayloadBudget.truncated(step.instruction, maxCharacters: TrackerExportPayloadBudget.listEntryLimit))"]

        if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedResult.isEmpty {
            parts.append("Expected: \(TrackerExportPayloadBudget.truncated(expectedResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit))")
        }

        if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actualResult.isEmpty {
            parts.append("Actual: \(TrackerExportPayloadBudget.truncated(actualResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit))")
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
        try annotationRenderer.annotatedScreenshotExports(for: issue, session: session).map { export in
            if let renderedFileName = export.renderedFileName {
                return "\(renderedFileName) from \(export.screenshotFileName) (\(export.timeLabel)) - \(export.summaries)"
            }

            return "\(export.screenshotFileName) (\(export.timeLabel)) - \(export.summaries)"
        }
    }



    private func searchJQL(for issue: ExtractedIssue, projectKey: String) -> String {
        let phrase = TrackerExportSupport.searchTerms(for: issue)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        \(Self.jqlProjectClause(projectKey)) AND statusCategory != Done AND (summary ~ "\\"\(phrase)\\"" OR description ~ "\\"\(phrase)\\"") ORDER BY updated DESC
        """
    }

    /// Builds the `project = "KEY"` JQL clause with the project key quoted and
    /// backslash/quote-escaped. Jira accepts a quoted project key, so quoting is
    /// behaviour-preserving for normal keys while neutralizing a malformed or
    /// operator-bearing key value before it reaches the JQL parser.
    static func jqlProjectClause(_ projectKey: String) -> String {
        let escaped = projectKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "project = \"\(escaped)\""
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
    let id: String
    let name: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let normalizedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedID.isEmpty {
            try container.encode(normalizedID, forKey: .id)
            return
        }

        try container.encode(name, forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
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



private struct JiraCreateMetadataProjectsResponse: Decodable {
    let projects: [JiraProjectSummary]
    let maxResults: Int?
    let total: Int

    private enum CodingKeys: String, CodingKey {
        case projects
        case values
        case maxResults
        case total
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([JiraProjectSummary].self, forKey: .projects)
            ?? container.decodeIfPresent([JiraProjectSummary].self, forKey: .values)
            ?? []
        maxResults = try container.decodeIfPresent(Int.self, forKey: .maxResults)
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? projects.count
    }
}

private struct JiraProjectSummary: Decodable {
    let id: String?
    let key: String?
    let name: String?

    var option: JiraProjectOption? {
        guard let normalizedKey = key?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? normalizedKey
        return JiraProjectOption(projectID: id, key: normalizedKey, name: normalizedName)
    }
}

private struct JiraCreateMetaIssueTypesResponse: Decodable {
    let issueTypes: [JiraProjectIssueType]

    private enum CodingKeys: String, CodingKey {
        case issueTypes
        case values
    }

    init(from decoder: any Decoder) throws {
        if let issueTypes = try? [JiraProjectIssueType](from: decoder) {
            self.issueTypes = issueTypes
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        issueTypes = try container.decodeIfPresent([JiraProjectIssueType].self, forKey: .issueTypes)
            ?? container.decodeIfPresent([JiraProjectIssueType].self, forKey: .values)
            ?? []
    }
}

private struct JiraProjectIssueType: Decodable {
    let id: String?
    let name: String?

    var option: JiraIssueTypeOption? {
        guard let normalizedID = id?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
              let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        return JiraIssueTypeOption(id: normalizedID, name: normalizedName)
    }
}

private struct JiraCreateFieldMetadataResponse: Decodable {
    let fields: [JiraCreateFieldMetadata]

    private enum CodingKeys: String, CodingKey {
        case fields
        case values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fields = try container.decodeIfPresent([JiraCreateFieldMetadata].self, forKey: .fields)
            ?? container.decodeIfPresent([JiraCreateFieldMetadata].self, forKey: .values)
            ?? []
    }
}

private struct JiraCreateFieldMetadata: Decodable {
    let fieldID: String?
    let key: String?
    let name: String?
    let required: Bool

    enum CodingKeys: String, CodingKey {
        case fieldID = "fieldId"
        case key
        case name
        case required
    }

    var isSystemFieldSupportedByBugNarrator: Bool {
        switch key {
        case "project", "summary", "issuetype", "description":
            return true
        default:
            return false
        }
    }

    var displayName: String {
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedFieldID = fieldID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return normalizedName ?? normalizedFieldID ?? key ?? "Unknown field"
    }
}
