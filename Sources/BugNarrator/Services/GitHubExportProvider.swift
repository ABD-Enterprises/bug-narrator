import Foundation

actor GitHubExportProvider {
    private let session: URLSession
    private let logger = DiagnosticsLogger(category: .export)

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
            let request = try makeURLRequest(issue: issue, session: reviewSession, configuration: configuration)

            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AppError.exportFailure("GitHub returned an invalid response.")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw mapGitHubError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
                }

                let payload = try JSONDecoder().decode(GitHubIssueResponse.self, from: data)
                results.append(
                    ExportResult(
                        sourceIssueID: issue.id,
                        destination: .github,
                        remoteIdentifier: "#\(payload.number)",
                        remoteURL: payload.htmlURL
                    )
                )
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
                let mappedError = OpenAIErrorMapper.mapTransportError(error, fallback: AppError.exportFailure)
                throw partialExportError(mappedError, successfulCount: results.count)
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

    func makeURLRequest(
        issue: ExtractedIssue,
        session reviewSession: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) throws -> URLRequest {
        let owner = configuration.owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.owner
        let repository = configuration.repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.repository
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/issues")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(
            GitHubIssueRequest(
                title: issue.title,
                body: makeIssueBody(issue: issue, session: reviewSession),
                labels: configuration.labels.isEmpty ? nil : configuration.labels
            )
        )
        return request
    }

    private func makeIssueBody(issue: ExtractedIssue, session: TranscriptSession) -> String {
        var lines: [String] = [
            "## Summary",
            issue.summary,
            "",
            "## Evidence",
            issue.evidenceExcerpt,
            ""
        ]

        if let timestampLabel = issue.timestampLabel {
            lines.append("- Transcript time: `\(timestampLabel)`")
        }

        lines.append("- Severity: \(issue.severity.rawValue)")

        if let component = issue.component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            lines.append("- Component: \(component)")
        }

        lines.append("- Deduplication hint: `\(issue.deduplicationHint)`")

        if let sectionTitle = issue.sectionTitle, !sectionTitle.isEmpty {
            lines.append("- Transcript section: \(sectionTitle)")
        }

        if let confidenceLabel = issue.confidenceLabel {
            lines.append("- Confidence: \(confidenceLabel)")
        }

        if issue.requiresReview {
            lines.append("- Review needed: Yes")
        }

        if !issue.reproductionSteps.isEmpty {
            lines.append("")
            lines.append("## Reproduction Steps")

            for (index, step) in issue.reproductionSteps.enumerated() {
                lines.append("\(index + 1). \(step.instruction)")

                if let expectedResult = step.expectedResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !expectedResult.isEmpty {
                    lines.append("   - Expected: \(expectedResult)")
                }

                if let actualResult = step.actualResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !actualResult.isEmpty {
                    lines.append("   - Actual: \(actualResult)")
                }

                if let reference = reproductionStepReference(step, session: session) {
                    lines.append("   - Reference: \(reference)")
                }
            }
        }

        let screenshots = session.screenshots(for: issue)
        if !screenshots.isEmpty {
            lines.append("")
            lines.append("## Related Screenshots")
            for screenshot in screenshots {
                lines.append("- \(screenshot.fileName) (`\(screenshot.timeLabel)`) - attach manually from the exported session bundle if needed.")
            }
        }

        lines.append("")
        lines.append("## Source")
        lines.append("Exported from BugNarrator. Review against the raw transcript before triage.")

        return lines.joined(separator: "\n")
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

    private func mapGitHubError(
        statusCode: Int,
        data: Data,
        configuration: GitHubExportConfiguration
    ) -> AppError {
        let message = decodeGitHubMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let normalizedMessage = message.lowercased()

        if statusCode == 401 || statusCode == 403 {
            if normalizedMessage.contains("rate limit") {
                return .exportFailure("GitHub rate limited the request. Wait a moment and try again.")
            }

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

    private func partialExportError(_ error: AppError, successfulCount: Int) -> AppError {
        guard successfulCount > 0 else {
            return error
        }

        return .exportFailure(
            "GitHub exported \(successfulCount) issue\(successfulCount == 1 ? "" : "s") before failing. \(error.userMessage)"
        )
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

private struct GitHubErrorResponse: Decodable {
    let message: String
}
