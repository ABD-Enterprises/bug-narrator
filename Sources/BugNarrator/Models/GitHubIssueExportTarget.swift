import Foundation

struct GitHubIssueExportTarget: Codable, Equatable {
    var repositoryID: String?
    var owner: String
    var repository: String
    var labels: [String]

    init(
        repositoryID: String? = nil,
        owner: String = "",
        repository: String = "",
        labels: [String] = []
    ) {
        self.repositoryID = repositoryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        self.repository = repository.trimmingCharacters(in: .whitespacesAndNewlines)
        self.labels = labels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var isComplete: Bool {
        !owner.isEmpty && !repository.isEmpty
    }

    var displayLabel: String {
        isComplete ? "\(owner)/\(repository)" : "Choose a GitHub repository"
    }
}
