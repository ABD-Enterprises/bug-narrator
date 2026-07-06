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
