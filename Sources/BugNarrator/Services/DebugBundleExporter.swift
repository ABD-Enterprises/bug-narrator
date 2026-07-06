import AppKit
import Darwin
import Foundation
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

extension DebugBundleExporter: DebugBundleExporting {}
