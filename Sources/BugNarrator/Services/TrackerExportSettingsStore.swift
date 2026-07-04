import Foundation

/// Owns the `UserDefaults` persistence for the GitHub/Jira tracker export
/// **config** fields (repository/project/issue-type selection), extracted from
/// `SettingsStore` (#429 slice 2).
///
/// Like `RecordingPreferencesStore`, this is a plain value type, **not** an
/// `ObservableObject`: `SettingsStore` remains the observable facade — it keeps
/// the `@Published` properties, all observation, the cascade-clear rules (which
/// mutate other published properties), and the `load()` reads (via its
/// `stringValue` helper, preserving legacy-defaults-domain migration). This store
/// owns only the keys and the writes.
///
/// The GitHub/Jira tokens and the Jira email are Keychain secrets and are NOT
/// handled here (they stay in `SettingsStore` until a later slice). The default
/// keys are unchanged, so no migration is required.
struct TrackerExportSettingsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    enum Keys {
        static let githubRepositoryOwner = "settings.githubRepositoryOwner"
        static let githubRepositoryName = "settings.githubRepositoryName"
        static let githubRepositoryID = "settings.githubRepositoryID"
        static let githubDefaultLabels = "settings.githubDefaultLabels"
        static let jiraBaseURL = "settings.jiraBaseURL"
        static let jiraProjectID = "settings.jiraProjectID"
        static let jiraProjectKey = "settings.jiraProjectKey"
        static let jiraIssueTypeID = "settings.jiraIssueTypeID"
        static let jiraIssueType = "settings.jiraIssueType"
    }

    func persist(githubRepositoryOwner: String) {
        defaults.set(githubRepositoryOwner, forKey: Keys.githubRepositoryOwner)
    }

    func persist(githubRepositoryName: String) {
        defaults.set(githubRepositoryName, forKey: Keys.githubRepositoryName)
    }

    func persist(githubRepositoryID: String) {
        defaults.set(githubRepositoryID, forKey: Keys.githubRepositoryID)
    }

    func persist(githubDefaultLabels: String) {
        defaults.set(githubDefaultLabels, forKey: Keys.githubDefaultLabels)
    }

    func persist(jiraBaseURL: String) {
        defaults.set(jiraBaseURL, forKey: Keys.jiraBaseURL)
    }

    func persist(jiraProjectKey: String) {
        defaults.set(jiraProjectKey, forKey: Keys.jiraProjectKey)
    }

    func persist(jiraProjectID: String) {
        defaults.set(jiraProjectID, forKey: Keys.jiraProjectID)
    }

    func persist(jiraIssueType: String) {
        defaults.set(jiraIssueType, forKey: Keys.jiraIssueType)
    }

    func persist(jiraIssueTypeID: String) {
        defaults.set(jiraIssueTypeID, forKey: Keys.jiraIssueTypeID)
    }
}
