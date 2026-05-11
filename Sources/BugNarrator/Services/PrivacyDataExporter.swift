import AppKit
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

struct PrivacyDataExporter {
    private let fileManager: FileManager
    private let bundleWriter: AtomicBundleDirectoryWriter
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bundleWriter = AtomicBundleDirectoryWriter(fileManager: fileManager)
    }

    @MainActor
    func export(
        sessions: [TranscriptSession],
        settings: PrivacyDataExportSettingsSnapshot,
        diagnostics: PrivacyDataExportDiagnosticsSnapshot
    ) throws -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Export Data"
        openPanel.message = "Choose a folder for your BugNarrator data export."

        guard openPanel.runModal() == .OK, let destinationRoot = openPanel.url else {
            return nil
        }

        return try writeBundle(
            sessions: sessions,
            settings: settings,
            diagnostics: diagnostics,
            to: destinationRoot
        )
    }

    func writeBundle(
        sessions: [TranscriptSession],
        settings: PrivacyDataExportSettingsSnapshot,
        diagnostics: PrivacyDataExportDiagnosticsSnapshot,
        to destinationRoot: URL
    ) throws -> URL {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try bundleWriter.writeBundle(
            in: destinationRoot,
            suggestedName: suggestedBundleName()
        ) { bundleDirectoryURL in
            let manifest = PrivacyDataExportManifest(
                generatedAt: Date(),
                sessionCount: sessions.count,
                includesSecrets: false,
                exportedFiles: [
                    "manifest.json",
                    "sessions.json",
                    "settings.json",
                    "diagnostics.json"
                ],
                notes: [
                    "This export includes local BugNarrator session data.",
                    "OpenAI API keys, GitHub tokens, Jira credentials, and Keychain-only secrets are not included.",
                    "Settings metadata and local diagnostics context are included in sanitized form.",
                    "Screenshot files remain referenced by their existing session metadata; files outside this export are not copied."
                ]
            )

            try encoder.encode(manifest).write(
                to: bundleDirectoryURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
            try encoder.encode(sessions).write(
                to: bundleDirectoryURL.appendingPathComponent("sessions.json"),
                options: [.atomic]
            )
            try encoder.encode(settings).write(
                to: bundleDirectoryURL.appendingPathComponent("settings.json"),
                options: [.atomic]
            )
            try encoder.encode(diagnostics).write(
                to: bundleDirectoryURL.appendingPathComponent("diagnostics.json"),
                options: [.atomic]
            )
        }
    }

    private func suggestedBundleName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "BugNarrator-Data-Export-\(formatter.string(from: Date()))"
    }
}

struct LocalPrivacyDataManager: @unchecked Sendable {
    private let fileManager: FileManager
    private let appSupportURL: URL
    private let telemetryRecorder: OperationalTelemetryRecorder
    private let diagnosticsStore: DiagnosticsLogStore

    init(
        fileManager: FileManager = .default,
        appSupportURL: URL = AppSupportLocation.appDirectory(fileManager: .default),
        telemetryRecorder: OperationalTelemetryRecorder = OperationalTelemetryRecorder(),
        diagnosticsStore: DiagnosticsLogStore = BugNarratorDiagnostics.store
    ) {
        self.fileManager = fileManager
        self.appSupportURL = appSupportURL
        self.telemetryRecorder = telemetryRecorder
        self.diagnosticsStore = diagnosticsStore
    }

    func clearLocalSupportArtifacts() async {
        try? telemetryRecorder.clear()
        await diagnosticsStore.clear()

        let removableURLs = [
            appSupportURL.appendingPathComponent("RecoveredRecordings", isDirectory: true),
            appSupportURL.appendingPathComponent("export-receipts.json", isDirectory: false)
        ]

        for url in removableURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
