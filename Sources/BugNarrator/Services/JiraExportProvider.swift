import Foundation

actor JiraExportProvider {
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

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.exportFailure("Jira returned an invalid response.")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw mapJiraError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
                }

                let payload = try JSONDecoder().decode(JiraIssueResponse.self, from: data)
                let remoteURL = configuration.baseURL.appending(path: "browse/\(payload.key)")
                try await receiptStore.markSucceeded(
                    fingerprint: fingerprint,
                    sourceIssueID: issue.id,
                    destination: .jira,
                    targetIdentity: configuration.targetIdentity,
                    remoteIdentifier: payload.key,
                    remoteURL: remoteURL
                )
                let result = ExportResult(
                    sourceIssueID: issue.id,
                    destination: .jira,
                    remoteIdentifier: payload.key,
                    remoteURL: remoteURL
                )
                results.append(result)
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
                        "jira_export_reconciliation_failed",
                        (error as? AppError)?.userMessage ?? error.localizedDescription,
                        metadata: ["source_issue_id": issue.id.uuidString]
                    )
                }

                if error is AppError {
                    try? await receiptStore.clearReceipt(for: fingerprint)
                }
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

    func validate(configuration: JiraExportConfiguration) async throws {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "Jira export requires a base URL, email, API token, project key, and issue type."
            )
        }

        let issueTypes = try await fetchIssueTypes(
            for: configuration.projectKey,
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
            let request = makeCreateMetadataProjectsRequest(configuration: configuration, startAt: startAt)
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

            let payload = try JSONDecoder().decode(JiraCreateMetadataProjectsResponse.self, from: data)
            projects.append(
                contentsOf: payload.projects.map {
                    JiraProjectOption(projectID: $0.id, key: $0.key, name: $0.name)
                }
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
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        guard configuration.isComplete, !projectKey.isEmpty else {
            throw AppError.exportConfigurationMissing(
                "Jira issue type discovery requires a base URL, email, API token, and project key."
            )
        }

        let payload = try await fetchCreateIssueTypesPayload(
            for: projectKey,
            configuration: configuration
        )
        var seenNames = Set<String>()
        return payload.issueTypes.compactMap { issueType in
            let normalizedName = issueType.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else {
                return nil
            }

            let key = normalizedName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seenNames.insert(key).inserted else {
                return nil
            }

            return JiraIssueTypeOption(id: issueType.id, name: normalizedName)
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

    private func makeCreateMetadataProjectsRequest(
        configuration: JiraConnectionConfiguration,
        startAt: Int
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "rest/api/3/issue/createmeta"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "startAt", value: "\(startAt)"),
            .init(name: "maxResults", value: "50")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(
            "Basic \(basicAuthValue(email: configuration.email, apiToken: configuration.apiToken))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeCreateIssueTypesRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "rest/api/3/issue/createmeta/\(projectKey)/issuetypes"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "startAt", value: "0"),
            .init(name: "maxResults", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(
            "Basic \(basicAuthValue(email: configuration.email, apiToken: configuration.apiToken))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func makeCreateFieldMetadataRequest(
        configuration: JiraConnectionConfiguration,
        projectKey: String,
        issueTypeID: String
    ) -> URLRequest {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "rest/api/3/issue/createmeta/\(projectKey)/issuetypes/\(issueTypeID)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            .init(name: "startAt", value: "0"),
            .init(name: "maxResults", value: "100")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(
            "Basic \(basicAuthValue(email: configuration.email, apiToken: configuration.apiToken))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetchCreateIssueTypesPayload(
        for projectKey: String,
        configuration: JiraConnectionConfiguration
    ) async throws -> JiraCreateMetaIssueTypesResponse {
        let request = makeCreateIssueTypesRequest(
            configuration: configuration,
            projectKey: projectKey
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

        return try JSONDecoder().decode(JiraCreateMetaIssueTypesResponse.self, from: data)
    }

    private func fetchRequiredCreateFields(
        for projectKey: String,
        issueTypeID: String,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraCreateFieldMetadata] {
        let request = makeCreateFieldMetadataRequest(
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

        let payload = try JSONDecoder().decode(JiraCreateFieldMetadataResponse.self, from: data)
        return payload.fields.filter(\.required)
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

    private func makeExportFingerprintSearchRequest(
        fingerprint: String,
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
                jql: #"project = \#(configuration.projectKey) AND description ~ "\"\#(TrackerExportFingerprint.marker(for: fingerprint))\"" ORDER BY created DESC"#,
                maxResults: 1,
                fields: ["summary", "description"]
            )
        )
        return request
    }

    private func basicAuthValue(email: String, apiToken: String) -> String {
        let rawValue = "\(email):\(apiToken)"
        return Data(rawValue.utf8).base64EncodedString()
    }

    private func existingExportResult(
        fingerprint: String,
        sourceIssueID: UUID,
        configuration: JiraExportConfiguration
    ) async throws -> ExportResult? {
        if let receipt = await receiptStore.receipt(for: fingerprint),
           let exportResult = receipt.asExportResult() {
            return exportResult
        }

        guard let receipt = await receiptStore.receipt(for: fingerprint),
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

    private func hardLimit(
        _ blocks: [JiraBlock],
        maxCharacters: Int
    ) -> [JiraBlock] {
        var characterBudget = 0
        var limitedBlocks: [JiraBlock] = []

        for block in blocks {
            let blockText = block.plainText
            let blockLength = blockText.count
            if characterBudget + blockLength <= maxCharacters {
                limitedBlocks.append(block)
                characterBudget += blockLength
                continue
            }

            let remainingCharacters = max(0, maxCharacters - characterBudget)
            guard remainingCharacters > 0 else {
                break
            }

            limitedBlocks.append(
                .paragraph(
                    text: TrackerExportPayloadBudget.truncated(
                        blockText,
                        maxCharacters: remainingCharacters
                    )
                )
            )
            break
        }

        return limitedBlocks
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

    var plainText: String {
        content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
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

    var plainText: String {
        let childText = content?.map(\.plainText).filter { !$0.isEmpty }.joined(separator: " ") ?? ""
        if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if childText.isEmpty {
                return text
            }

            return "\(text) \(childText)"
        }

        return childText
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

private struct JiraCreateMetadataProjectsResponse: Decodable {
    let projects: [JiraProjectSummary]
    let maxResults: Int?
    let total: Int
}

private struct JiraProjectSummary: Decodable {
    let id: String?
    let key: String
    let name: String
}

private struct JiraCreateMetaIssueTypesResponse: Decodable {
    let issueTypes: [JiraProjectIssueType]
}

private struct JiraProjectIssueType: Decodable {
    let id: String
    let name: String
}

private struct JiraCreateFieldMetadataResponse: Decodable {
    let fields: [JiraCreateFieldMetadata]
}

private struct JiraCreateFieldMetadata: Decodable {
    let fieldID: String
    let key: String
    let name: String
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
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fieldID : name
    }
}
