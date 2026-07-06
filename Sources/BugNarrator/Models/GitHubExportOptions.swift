import Foundation

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
