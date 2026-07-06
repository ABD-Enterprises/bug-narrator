import Foundation

struct DebugInfoSnapshot: Equatable {
    let appName: String
    let versionDescription: String
    let macOSVersion: String
    let architecture: String
    let activeTranscriptionModel: String
    let issueExtractionModel: String
    let logLevel: String
    let debugModeEnabled: Bool
    let sessionID: UUID?

    init(
        metadata: BugNarratorMetadata,
        settingsStore: SettingsStore,
        sessionID: UUID?
    ) {
        appName = metadata.appName
        versionDescription = metadata.versionDescription
        macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        architecture = SystemDiagnosticsInfo.currentArchitecture()
        activeTranscriptionModel = settingsStore.preferredModelValue
        issueExtractionModel = settingsStore.issueExtractionModelValue
        logLevel = BugNarratorDiagnostics.activeLogLevel().label
        debugModeEnabled = settingsStore.debugMode
        self.sessionID = sessionID
    }

    var clipboardText: String {
        [
            "\(appName) \(versionDescription)",
            "macOS: \(macOSVersion)",
            "Architecture: \(architecture)",
            "Transcription Model: \(activeTranscriptionModel)",
            "Issue Extraction Model: \(issueExtractionModel)",
            "Log Level: \(logLevel)",
            "Debug Mode: \(debugModeEnabled ? "Enabled" : "Disabled")",
            "Session ID: \(sessionID?.uuidString ?? "None")"
        ]
        .joined(separator: "\n")
    }

    var appVersionText: String {
        "\(appName) \(versionDescription)\n"
    }

    var macOSVersionText: String {
        "\(macOSVersion)\n"
    }
}
struct DebugBundleSnapshot {
    let debugInfo: DebugInfoSnapshot
    let sessionMetadata: DebugSessionMetadata
    let recentLogText: String
}
