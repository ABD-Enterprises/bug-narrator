import Foundation

extension JiraExportProvider {
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

    func existingExportResult(
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

    func reconcilePendingExport(
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

    private func searchJQL(for issue: ExtractedIssue, projectKey: String) -> String {
        let phrase = TrackerExportSupport.searchTerms(for: issue)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        \(Self.jqlProjectClause(projectKey)) AND statusCategory != Done AND (summary ~ "\\"\(phrase)\\"" OR description ~ "\\"\(phrase)\\"") ORDER BY updated DESC
        """
    }
}

struct JiraSearchRequest: Encodable {
    let jql: String
    let maxResults: Int
    let fields: [String]

    enum CodingKeys: String, CodingKey {
        case jql
        case maxResults = "maxResults"
        case fields
    }
}

struct JiraSearchResponse: Decodable {
    let issues: [JiraSearchIssue]
}

struct JiraSearchIssue: Decodable {
    let key: String
    let fields: JiraSearchIssueFields
}

struct JiraSearchIssueFields: Decodable {
    let summary: String
    let description: JiraADFNode?
}
