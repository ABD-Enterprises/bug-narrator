import Foundation

extension SettingsStore {
    var normalizedGitHubRepositoryOwner: String {
        githubRepositoryOwner.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitHubRepositoryName: String {
        githubRepositoryName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedGitHubRepositoryID: String {
        githubRepositoryID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraBaseURL: String {
        jiraBaseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    var normalizedJiraEmail: String {
        jiraEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraProjectKey: String {
        jiraProjectKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    var normalizedJiraProjectID: String {
        jiraProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraIssueType: String {
        jiraIssueType.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedJiraIssueTypeID: String {
        jiraIssueTypeID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
