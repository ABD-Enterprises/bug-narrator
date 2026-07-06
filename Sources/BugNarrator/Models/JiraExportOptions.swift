import Foundation

struct JiraProjectOption: Equatable, Identifiable {
    let projectID: String
    let key: String
    let name: String

    init(projectID: String? = nil, key: String, name: String) {
        self.projectID = projectID ?? key
        self.key = key
        self.name = name
    }

    var id: String { projectID }

    var displayLabel: String {
        "\(key) - \(name)"
    }
}

struct JiraIssueTypeOption: Equatable, Identifiable {
    let id: String
    let name: String
}

