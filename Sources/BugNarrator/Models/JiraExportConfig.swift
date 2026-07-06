import Foundation

struct JiraConnectionConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String

    var isComplete: Bool {
        !email.isEmpty && !apiToken.isEmpty
    }
}

struct JiraExportConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String
    let projectID: String?
    let projectKey: String
    let issueTypeID: String
    let issueTypeName: String

    init(
        baseURL: URL,
        email: String,
        apiToken: String,
        projectID: String? = nil,
        projectKey: String,
        issueTypeID: String = "",
        issueTypeName: String? = nil,
        issueType: String? = nil
    ) {
        self.baseURL = baseURL
        self.email = email
        self.apiToken = apiToken
        self.projectID = projectID
        self.projectKey = projectKey
        self.issueTypeID = issueTypeID
        self.issueTypeName = issueTypeName ?? issueType ?? ""
    }

    var isComplete: Bool {
        !email.isEmpty
            && !apiToken.isEmpty
            && !projectKey.isEmpty
            && !(issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 && issueTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var targetIdentity: String {
        let normalizedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? projectKey.uppercased()
        let normalizedIssueTypeID = issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedIssueTypeName = issueTypeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
            ?? "unknown"
        return "\(normalizedProjectID)::\(normalizedIssueTypeID ?? normalizedIssueTypeName)"
    }

    var issueExportTarget: JiraIssueExportTarget {
        JiraIssueExportTarget(
            projectID: projectID,
            projectKey: projectKey,
            issueTypeID: issueTypeID,
            issueTypeName: issueTypeName
        )
    }
}
