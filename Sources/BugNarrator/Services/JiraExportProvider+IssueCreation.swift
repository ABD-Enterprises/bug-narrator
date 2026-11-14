import Foundation

extension JiraExportProvider {
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

    func makeURLRequest(
        issue: ExtractedIssue,
        session reviewSession: TranscriptSession,
        configuration: JiraExportConfiguration,
        exportFingerprint: String? = nil
    ) throws -> URLRequest {
        let endpoint = configuration.baseURL.appending(path: "rest/api/3/issue")
        var request = try authenticatedRequest(
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
                    summary: TrackerExportPayloadBudget.trackerTitle(issue.title, maxCharacters: TrackerExportPayloadBudget.jiraSummaryLimit),
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
            let (data, response) = try await BoundedHTTPResponseReader.data(for: request, using: session, delegate: redirectPolicy)
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

    /// Neutralizes one untrusted description field.
    ///
    /// The Jira description is structured ADF, so the field is plain text and
    /// only the live mention and cross-reference triggers have to be defanged
    /// — the block-structure and link escapes a markdown body needs would
    /// only mangle it.
    private static func neutralizedDescriptionText(_ value: String) -> String {
        TrackerExportPayloadBudget.neutralizingUntrustedMentions(value)
    }

    private func makeDescription(
        issue: ExtractedIssue,
        session: TranscriptSession,
        exportFingerprint: String?
    ) throws -> JiraDocument {
        // Jira renders the description as structured ADF, so its text is plain
        // text rather than markdown — but it is still model- and
        // transcript-derived, and a tracker can show the same text again in
        // notifications and activity feeds. Every untrusted field below is
        // neutralized before it leaves the app, so no live mention or
        // cross-reference survives into the issue.
        var content: [JiraBlock] = [
            .paragraph(
                text: "Summary: \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(issue.summary, maxCharacters: TrackerExportPayloadBudget.issueSummaryLimit)))"
            ),
            .paragraph(
                text: "Evidence: \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(issue.evidenceExcerpt, maxCharacters: TrackerExportPayloadBudget.evidenceLimit)))"
            )
        ]

        var metadataLines: [String] = []
        if let timestampLabel = issue.timestampLabel {
            metadataLines.append("Transcript time: \(timestampLabel)")
        }
        metadataLines.append("Severity: \(issue.severity.rawValue)")
        if let component = issue.component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            metadataLines.append("Component: \(Self.neutralizedDescriptionText(component))")
        }
        metadataLines.append("Deduplication hint: \(Self.neutralizedDescriptionText(issue.deduplicationHint))")
        if let sectionTitle = issue.sectionTitle, !sectionTitle.isEmpty {
            metadataLines.append("Transcript section: \(Self.neutralizedDescriptionText(sectionTitle))")
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
                    text: "Tracker context: \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(note, maxCharacters: TrackerExportPayloadBudget.noteLimit)))"
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
        var parts = ["\(index + 1). \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(step.instruction, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))"]

        if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expectedResult.isEmpty {
            parts.append("Expected: \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(expectedResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
        }

        if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actualResult.isEmpty {
            parts.append("Actual: \(Self.neutralizedDescriptionText(TrackerExportPayloadBudget.truncated(actualResult, maxCharacters: TrackerExportPayloadBudget.listEntryLimit)))")
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
            // The annotation summaries are model-authored text.
            let summaries = Self.neutralizedDescriptionText(export.summaries)
            if let renderedFileName = export.renderedFileName {
                return "\(renderedFileName) from \(export.screenshotFileName) (\(export.timeLabel)) - \(summaries)"
            }

            return "\(export.screenshotFileName) (\(export.timeLabel)) - \(summaries)"
        }
    }
}

struct JiraIssueRequest: Encodable {
    let fields: JiraIssueFields
}

struct JiraIssueFields: Encodable {
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

struct JiraProjectField: Encodable {
    let key: String
}

struct JiraIssueTypeField: Encodable {
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

struct JiraIssueResponse: Decodable {
    let id: String
    let key: String
}
