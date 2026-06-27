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
        sessions: PrivacyDataSessionStream,
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

    /// Convenience overload for callers (and tests) that already hold a
    /// materialized session array.
    func writeBundle(
        sessions: [TranscriptSession],
        settings: PrivacyDataExportSettingsSnapshot,
        diagnostics: PrivacyDataExportDiagnosticsSnapshot,
        to destinationRoot: URL
    ) throws -> URL {
        try writeBundle(
            sessions: PrivacyDataSessionStream(sessions: sessions),
            settings: settings,
            diagnostics: diagnostics,
            to: destinationRoot
        )
    }

    func writeBundle(
        sessions: PrivacyDataSessionStream,
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
            // Stream sessions first so the manifest's `sessionCount` reflects the
            // number actually written. Sessions whose body can no longer be
            // decoded are skipped, so this can be fewer than the library entry
            // count — matching the pre-streaming behavior, where `allStored-
            // Sessions()` had already filtered out undecodable bodies.
            let writtenSessionCount = try writeSessionsArray(
                sessions,
                to: bundleDirectoryURL.appendingPathComponent("sessions.json")
            )

            let manifest = PrivacyDataExportManifest(
                generatedAt: Date(),
                sessionCount: writtenSessionCount,
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

    /// Streams the session array to `sessions.json` one element at a time so the
    /// whole library is never encoded into a single in-memory buffer. The output
    /// is byte-identical to `encoder.encode([TranscriptSession])` with the same
    /// `[.prettyPrinted, .sortedKeys]` formatting — each element is encoded on its
    /// own, re-indented one level, and joined exactly as the array encoder would.
    /// Returns the number of sessions actually written.
    @discardableResult
    private func writeSessionsArray(_ sessions: PrivacyDataSessionStream, to url: URL) throws -> Int {
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw AppError.storageFailure("Could not create the sessions export file.")
        }
        let handle = try FileHandle(forWritingTo: url)
        var didThrow = false
        defer {
            if didThrow { try? fileManager.removeItem(at: url) }
            try? handle.close()
        }

        do {
            var index = 0
            try sessions.forEach { session in
                let elementData = try encoder.encode(session)
                // First element follows `[\n`; subsequent elements follow `,\n`.
                try handle.write(contentsOf: Data((index == 0 ? "[\n" : ",\n").utf8))
                try handle.write(contentsOf: Self.indentedArrayElement(elementData))
                index += 1
            }
            // Match JSONEncoder's pretty output: an empty array is `[\n\n]`;
            // a non-empty one closes with `\n]`.
            try handle.write(contentsOf: Data((index == 0 ? "[\n\n]" : "\n]").utf8))
            return index
        } catch {
            didThrow = true
            throw error
        }
    }

    /// Re-indents a standalone pretty-printed JSON object by one level (two
    /// spaces) so it matches how the array encoder nests each element. Genuinely
    /// empty lines (which `JSONEncoder` emits inside empty containers) are left
    /// unindented, exactly as the array encoder leaves them.
    private static func indentedArrayElement(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
        let indented = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "  " + $0 }
            .joined(separator: "\n")
        return Data(indented.utf8)
    }

    private func suggestedBundleName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "BugNarrator-Data-Export-\(formatter.string(from: Date()))"
    }
}

extension PrivacyDataExporter: PrivacyDataExporting {}

// Thread-safety invariant: all stored properties are immutable `let`s, so the
// value carries no mutable shared state. The `@unchecked` only suppresses the
// non-Sendable `FileManager`/recorder/store members; each of those is either
// independently thread-safe or confined to the store's own actor/queue, so
// sharing this value across tasks introduces no data race.
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
            appSupportURL.appendingPathComponent("export-receipts.json", isDirectory: false),
            appSupportURL.appendingPathComponent("export-receipts.corrupt.json", isDirectory: false)
        ]

        for url in removableURLs where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}

extension LocalPrivacyDataManager: LocalPrivacyDataManaging {}
