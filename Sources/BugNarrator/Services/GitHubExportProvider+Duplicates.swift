import Foundation

extension GitHubExportProvider {
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

    func existingExportResult(
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

    func reconcilePendingExport(
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
}
