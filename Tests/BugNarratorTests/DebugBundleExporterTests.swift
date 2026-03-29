import XCTest
@testable import BugNarrator

@MainActor
final class DebugBundleExporterTests: XCTestCase {
    func testWriteBundleCreatesExpectedFilesWithoutCredentials() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("DebugBundleExporterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let defaultsSuiteName = "DebugBundleExporterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }

        let keychainService = MockKeychainService()
        let settingsStore = SettingsStore(defaults: defaults, keychainService: keychainService)
        settingsStore.apiKey = "fixture-openai-key"
        settingsStore.preferredModel = "whisper-1"
        settingsStore.issueExtractionModel = "gpt-4.1-mini"
        settingsStore.debugMode = true

        let snapshot = DebugBundleSnapshot(
            debugInfo: DebugInfoSnapshot(
                metadata: BugNarratorMetadata(
                    infoDictionary: [
                        "CFBundleDisplayName": "BugNarrator",
                        "CFBundleShortVersionString": "1.0.6",
                        "CFBundleVersion": "7"
                    ]
                ),
                settingsStore: settingsStore,
                sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
            ),
            sessionMetadata: DebugSessionMetadata(
                source: .transcript,
                sessionID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"),
                statusTitle: "Success",
                statusDetail: "Transcript ready.",
                errorMessage: nil,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_600),
                duration: 42,
                transcriptCharacterCount: 1200,
                sectionsCount: 3,
                markerCount: 2,
                screenshotCount: 1,
                issueCount: 4,
                summaryCharacterCount: 240,
                artifactsDirectoryExists: true,
                missingScreenshotFiles: ["capture-1.png"]
            ),
            recentLogText: """
            2026-03-15T12:00:00Z [INFO] [settings] debug_bundle_exported - Exported a local debug bundle.
            """
        )

        let exporter = DebugBundleExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(snapshot: snapshot, to: rootDirectoryURL)

        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("system-info.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("app-version.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("macos-version.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("recent-log.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("session-metadata.json").path))

        let appVersion = try String(contentsOf: bundleURL.appendingPathComponent("app-version.txt"))
        XCTAssertTrue(appVersion.contains("BugNarrator Version 1.0.6 (7)"))

        let sessionMetadata = try String(contentsOf: bundleURL.appendingPathComponent("session-metadata.json"))
        XCTAssertTrue(sessionMetadata.contains("\"issueCount\" : 4"))
        XCTAssertFalse(sessionMetadata.contains("fixture-openai-key"))

        let systemInfo = try String(contentsOf: bundleURL.appendingPathComponent("system-info.json"))
        XCTAssertTrue(systemInfo.contains("\"activeTranscriptionModel\" : \"whisper-1\""))
        XCTAssertFalse(systemInfo.contains("fixture-openai-key"))

        let recentLog = try String(contentsOf: bundleURL.appendingPathComponent("recent-log.txt"))
        XCTAssertTrue(recentLog.contains("debug bundle"))
        XCTAssertFalse(recentLog.contains("fixture-openai-key"))
    }
}
