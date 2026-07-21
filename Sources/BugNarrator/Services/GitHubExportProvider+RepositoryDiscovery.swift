import Foundation

extension GitHubExportProvider {
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
}
