import AppKit
import Foundation

struct PrivacyDataExportManifest: Encodable {
    let generatedAt: Date
    let sessionCount: Int
    let includesSecrets: Bool
    let notes: [String]
}

struct PrivacyDataExporter {
    private let fileManager: FileManager
    private let bundleWriter: AtomicBundleDirectoryWriter
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.bundleWriter = AtomicBundleDirectoryWriter(fileManager: fileManager)
    }

    func export(sessions: [TranscriptSession]) throws -> URL? {
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

        return try writeBundle(sessions: sessions, to: destinationRoot)
    }

    func writeBundle(sessions: [TranscriptSession], to destinationRoot: URL) throws -> URL {
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
                notes: [
                    "This export includes local BugNarrator session data.",
                    "OpenAI API keys, GitHub tokens, Jira credentials, and Keychain-only secrets are not included.",
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
        }
    }

    private func suggestedBundleName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "BugNarrator-Data-Export-\(formatter.string(from: Date()))"
    }
}
