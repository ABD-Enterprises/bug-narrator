import Foundation

extension SettingsStore {
    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedGitHubToken: String {
        githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasGitHubToken: Bool {
        !trimmedGitHubToken.isEmpty
    }

    var githubDefaultLabelsList: [String] {
        githubDefaultLabels
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var trimmedJiraAPIToken: String {
        jiraAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasJiraAPIToken: Bool {
        !trimmedJiraAPIToken.isEmpty
    }
}
