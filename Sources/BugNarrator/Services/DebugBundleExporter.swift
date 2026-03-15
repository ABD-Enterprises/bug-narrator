import AppKit
import Darwin
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

struct DebugSessionMetadata: Codable, Equatable {
    enum Source: String, Codable {
        case activeRecording
        case transcript
        case none
    }

    let source: Source
    let sessionID: UUID?
    let statusTitle: String
    let statusDetail: String?
    let errorMessage: String?
    let createdAt: Date?
    let updatedAt: Date?
    let duration: TimeInterval?
    let transcriptCharacterCount: Int?
    let sectionsCount: Int
    let markerCount: Int
    let screenshotCount: Int
    let issueCount: Int
    let summaryCharacterCount: Int?
    let artifactsDirectoryExists: Bool
    let missingScreenshotFiles: [String]

    static func make(
        currentTranscript: TranscriptSession?,
        displayedTranscript: TranscriptSession?,
        activeRecordingSession: RecordingSessionDraft?,
        status: AppStatus,
        currentError: AppError?
    ) -> DebugSessionMetadata {
        if let activeRecordingSession {
            return DebugSessionMetadata(
                source: .activeRecording,
                sessionID: activeRecordingSession.sessionID,
                statusTitle: status.title,
                statusDetail: status.detail,
                errorMessage: currentError?.userMessage,
                createdAt: nil,
                updatedAt: nil,
                duration: nil,
                transcriptCharacterCount: nil,
                sectionsCount: 0,
                markerCount: activeRecordingSession.markers.count,
                screenshotCount: activeRecordingSession.screenshots.count,
                issueCount: 0,
                summaryCharacterCount: nil,
                artifactsDirectoryExists: FileManager.default.fileExists(
                    atPath: activeRecordingSession.artifactsDirectoryURL.path
                ),
                missingScreenshotFiles: activeRecordingSession.screenshots.compactMap { screenshot in
                    FileManager.default.fileExists(atPath: screenshot.fileURL.path) ? nil : screenshot.fileName
                }
            )
        }

        if let session = displayedTranscript ?? currentTranscript {
            let missingScreenshotFiles = session.screenshots.compactMap { screenshot in
                FileManager.default.fileExists(atPath: screenshot.fileURL.path) ? nil : screenshot.fileName
            }

            return DebugSessionMetadata(
                source: .transcript,
                sessionID: session.id,
                statusTitle: status.title,
                statusDetail: status.detail,
                errorMessage: currentError?.userMessage,
                createdAt: session.createdAt,
                updatedAt: session.updatedAt,
                duration: session.duration,
                transcriptCharacterCount: session.transcript.count,
                sectionsCount: session.sections.count,
                markerCount: session.markerCount,
                screenshotCount: session.screenshotCount,
                issueCount: session.issueCount,
                summaryCharacterCount: session.summaryText.count,
                artifactsDirectoryExists: session.artifactsDirectoryURL.map {
                    FileManager.default.fileExists(atPath: $0.path)
                } ?? false,
                missingScreenshotFiles: missingScreenshotFiles
            )
        }

        return DebugSessionMetadata(
            source: .none,
            sessionID: nil,
            statusTitle: status.title,
            statusDetail: status.detail,
            errorMessage: currentError?.userMessage,
            createdAt: nil,
            updatedAt: nil,
            duration: nil,
            transcriptCharacterCount: nil,
            sectionsCount: 0,
            markerCount: 0,
            screenshotCount: 0,
            issueCount: 0,
            summaryCharacterCount: nil,
            artifactsDirectoryExists: false,
            missingScreenshotFiles: []
        )
    }
}

struct DebugBundleSnapshot {
    let debugInfo: DebugInfoSnapshot
    let sessionMetadata: DebugSessionMetadata
    let recentLogText: String
}

private struct DebugSystemInfoDocument: Codable {
    let generatedAt: Date
    let appName: String
    let versionDescription: String
    let macOSVersion: String
    let architecture: String
    let activeTranscriptionModel: String
    let issueExtractionModel: String
    let logLevel: String
    let debugModeEnabled: Bool
}

@MainActor
struct DebugBundleExporter {
    private let fileManager: FileManager
    private let bundleWriter: AtomicBundleDirectoryWriter
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bundleWriter = AtomicBundleDirectoryWriter(fileManager: fileManager)
    }

    func export(snapshot: DebugBundleSnapshot) throws -> URL? {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Export Debug Bundle"
        openPanel.message = "Choose a folder for the BugNarrator debug bundle."

        guard openPanel.runModal() == .OK, let destinationRoot = openPanel.url else {
            return nil
        }

        return try writeBundle(snapshot: snapshot, to: destinationRoot)
    }

    func writeBundle(snapshot: DebugBundleSnapshot, to destinationRoot: URL) throws -> URL {
        let systemInfoDocument = DebugSystemInfoDocument(
            generatedAt: Date(),
            appName: snapshot.debugInfo.appName,
            versionDescription: snapshot.debugInfo.versionDescription,
            macOSVersion: snapshot.debugInfo.macOSVersion,
            architecture: snapshot.debugInfo.architecture,
            activeTranscriptionModel: snapshot.debugInfo.activeTranscriptionModel,
            issueExtractionModel: snapshot.debugInfo.issueExtractionModel,
            logLevel: snapshot.debugInfo.logLevel,
            debugModeEnabled: snapshot.debugInfo.debugModeEnabled
        )

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        return try bundleWriter.writeBundle(
            in: destinationRoot,
            suggestedName: suggestedBundleName()
        ) { bundleDirectoryURL in
            try encoder.encode(systemInfoDocument).write(
                to: bundleDirectoryURL.appendingPathComponent("system-info.json"),
                options: [.atomic]
            )
            try snapshot.debugInfo.appVersionText.write(
                to: bundleDirectoryURL.appendingPathComponent("app-version.txt"),
                atomically: true,
                encoding: .utf8
            )
            try snapshot.debugInfo.macOSVersionText.write(
                to: bundleDirectoryURL.appendingPathComponent("macos-version.txt"),
                atomically: true,
                encoding: .utf8
            )
            try snapshot.recentLogText.write(
                to: bundleDirectoryURL.appendingPathComponent("recent-log.txt"),
                atomically: true,
                encoding: .utf8
            )
            try encoder.encode(snapshot.sessionMetadata).write(
                to: bundleDirectoryURL.appendingPathComponent("session-metadata.json"),
                options: [.atomic]
            )
        }
    }

    private func suggestedBundleName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "bugnarrator-debug-bundle-\(formatter.string(from: Date()))"
    }
}

enum SystemDiagnosticsInfo {
    static func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineField = systemInfo.machine

        let machine = withUnsafePointer(to: machineField) { pointer -> String in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: MemoryLayout.size(ofValue: machineField)
            ) { reboundPointer in
                String(cString: reboundPointer)
            }
        }

        return machine.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
