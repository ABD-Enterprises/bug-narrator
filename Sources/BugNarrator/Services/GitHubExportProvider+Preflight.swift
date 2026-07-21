import Foundation

extension GitHubExportProvider {
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
}
