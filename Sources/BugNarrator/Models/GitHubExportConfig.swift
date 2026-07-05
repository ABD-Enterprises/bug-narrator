import Foundation

struct GitHubExportConfiguration: Equatable {
    let token: String
    let repositoryID: String?
    let owner: String
    let repository: String
    let labels: [String]

    init(
        token: String,
        repositoryID: String? = nil,
        owner: String,
        repository: String,
        labels: [String]
    ) {
        self.token = token
        self.repositoryID = repositoryID
        self.owner = owner
        self.repository = repository
        self.labels = labels
    }

    var isComplete: Bool {
        !token.isEmpty && !owner.isEmpty && !repository.isEmpty
    }

    var targetIdentity: String {
        repositoryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(owner.lowercased())/\(repository.lowercased())"
    }

    var issueExportTarget: GitHubIssueExportTarget {
        GitHubIssueExportTarget(
            repositoryID: repositoryID,
            owner: owner,
            repository: repository,
            labels: labels
        )
    }
}

struct GitHubRepositoryOption: Equatable, Identifiable {
    let repositoryID: String
    let owner: String
    let name: String
    let description: String?

    init(
        repositoryID: String? = nil,
        owner: String,
        name: String,
        description: String?
    ) {
        self.repositoryID = repositoryID ?? "\(owner.lowercased())/\(name.lowercased())"
        self.owner = owner
        self.name = name
        self.description = description
    }

    var id: String { repositoryID }

    var fullName: String {
        "\(owner)/\(name)"
    }

    var displayLabel: String {
        guard let description, !description.isEmpty else {
            return fullName
        }

        return "\(fullName) - \(description)"
    }
}
