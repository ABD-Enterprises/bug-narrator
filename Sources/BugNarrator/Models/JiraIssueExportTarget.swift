import Foundation

struct JiraIssueExportTarget: Codable, Equatable {
    var projectID: String?
    var projectKey: String
    var projectName: String?
    var issueTypeID: String
    var issueTypeName: String

    init(
        projectID: String? = nil,
        projectKey: String = "",
        projectName: String? = nil,
        issueTypeID: String = "",
        issueTypeName: String = ""
    ) {
        self.projectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.projectKey = projectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.projectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.issueTypeID = issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.issueTypeName = issueTypeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !projectKey.isEmpty && (!issueTypeID.isEmpty || !issueTypeName.isEmpty)
    }

    var projectDisplayLabel: String {
        guard let projectName else {
            return projectKey.isEmpty ? "Choose a Jira project" : projectKey
        }

        return "\(projectKey) - \(projectName)"
    }
}
