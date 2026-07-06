import Foundation

struct PrivacyDataExportManifest: Encodable {
    let generatedAt: Date
    let sessionCount: Int
    let includesSecrets: Bool
    let exportedFiles: [String]
    let notes: [String]
}

struct PrivacyDataExportSettingsSnapshot: Codable, Equatable {
    let openAIBaseURL: String
    let transcriptionModel: String
    let languageHint: String?
    let issueExtractionModel: String
    let autoCopyTranscript: Bool
    let autoExtractIssues: Bool
    let debugModeEnabled: Bool
    let openAtStartupEnabled: Bool
    let gitHubRepositoryOwner: String?
    let gitHubRepositoryName: String?
    let gitHubDefaultLabels: [String]
    let jiraBaseURL: String?
    let jiraProjectKey: String?
    let jiraIssueType: String?

    init(settingsStore: SettingsStore) {
        openAIBaseURL = settingsStore.openAIBaseURLValue.absoluteString
        transcriptionModel = settingsStore.preferredModelValue
        languageHint = settingsStore.normalizedLanguageHint
        issueExtractionModel = settingsStore.issueExtractionModelValue
        autoCopyTranscript = settingsStore.autoCopyTranscript
        autoExtractIssues = settingsStore.autoExtractIssues
        debugModeEnabled = settingsStore.debugMode
        openAtStartupEnabled = settingsStore.openAtStartup
        gitHubRepositoryOwner = settingsStore.normalizedGitHubRepositoryOwner.nilIfEmpty
        gitHubRepositoryName = settingsStore.normalizedGitHubRepositoryName.nilIfEmpty
        gitHubDefaultLabels = settingsStore.githubDefaultLabelsList
        jiraBaseURL = settingsStore.normalizedJiraBaseURL.nilIfEmpty
        jiraProjectKey = settingsStore.normalizedJiraProjectKey.nilIfEmpty
        jiraIssueType = settingsStore.normalizedJiraIssueType.nilIfEmpty
    }
}

struct PrivacyDataExportDiagnosticsSnapshot: Codable, Equatable {
    let appName: String
    let versionDescription: String
    let macOSVersion: String
    let architecture: String
    let activeTranscriptionModel: String
    let issueExtractionModel: String
    let logLevel: String
    let debugModeEnabled: Bool
    let recentTelemetryEvents: [OperationalTelemetryEvent]
    let recentDiagnosticsLog: String
    let exportHistory: [ExportReceipt]
}

/// A lazy source of stored sessions for export. The exporter pulls sessions one
/// at a time via `forEach`, so the whole library never has to be materialized in
/// memory simultaneously (#508). `count` is the number of sessions `forEach` will
/// yield, known up front from the lightweight library index.
struct PrivacyDataSessionStream {
    let count: Int
    let forEach: (_ body: (TranscriptSession) throws -> Void) throws -> Void

    /// Convenience for callers (and tests) that already hold a materialized array.
    init(sessions: [TranscriptSession]) {
        count = sessions.count
        forEach = { body in
            for session in sessions {
                try body(session)
            }
        }
    }

    init(count: Int, forEach: @escaping (_ body: (TranscriptSession) throws -> Void) throws -> Void) {
        self.count = count
        self.forEach = forEach
    }
}
