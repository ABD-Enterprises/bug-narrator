import Foundation

extension GitHubExportProvider {
    func mapGitHubError(
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

    func url(from components: URLComponents) throws -> URL {
        guard let url = components.url else {
            throw AppError.exportFailure("GitHub search query could not be constructed.")
        }

        return url
    }

    /// Produces a GitHub REST request with the shared Bearer auth, Accept, and
    /// User-Agent headers applied. Pass `includesJSONContentType` for requests
    /// that carry a JSON body.
    func authenticatedRequest(
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

    func repositoryEndpoint(configuration: GitHubExportConfiguration) -> URL {
        let owner = configuration.owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.owner
        let repository = configuration.repository.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? configuration.repository
        return URL(string: "https://api.github.com/repos/\(owner)/\(repository)")!
    }

    func issueEndpoint(configuration: GitHubExportConfiguration) -> URL {
        repositoryEndpoint(configuration: configuration).appendingPathComponent("issues")
    }
}
