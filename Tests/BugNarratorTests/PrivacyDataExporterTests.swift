import Foundation
import XCTest
@testable import BugNarrator

final class PrivacyDataExporterTests: XCTestCase {
    func testPrivacyDataExporterWritesManifestSessionsSettingsAndDiagnosticsWithoutSecrets() throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-PrivacyDataExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let exporter = PrivacyDataExporter()
        let session = makeSampleTranscriptSession(index: 1)
        let settingsStore = SettingsStore(
            defaults: UserDefaults(suiteName: "BugNarrator-PrivacyDataExporterTests-\(UUID().uuidString)") ?? .standard,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        settingsStore.githubToken = "github_pat_secret"
        settingsStore.jiraAPIToken = "jira-secret"
        settingsStore.jiraEmail = "person@example.com"
        settingsStore.githubRepositoryOwner = "deffenda"
        settingsStore.githubRepositoryName = "bug-narrator"
        settingsStore.githubDefaultLabels = "bug,export"
        settingsStore.jiraBaseURL = "https://example.atlassian.net"
        settingsStore.jiraProjectKey = "UCAP"
        settingsStore.jiraIssueType = "Task"
        settingsStore.refreshSecretsForUserInitiatedAccess()
        let settings = PrivacyDataExportSettingsSnapshot(settingsStore: settingsStore)
        let diagnostics = PrivacyDataExportDiagnosticsSnapshot(
            appName: "BugNarrator",
            versionDescription: "1.0.33 (34)",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            activeTranscriptionModel: "whisper-1",
            issueExtractionModel: "gpt-4.1-mini",
            logLevel: "info",
            debugModeEnabled: false,
            recentTelemetryEvents: [
                OperationalTelemetryEvent(name: "recording_started", metadata: ["has_openai_key": "yes"])
            ],
            recentDiagnosticsLog: "2026-05-11T00:00:00Z [INFO] [settings] privacy_data_exported",
            exportHistory: []
        )

        let exportURL = try exporter.writeBundle(
            sessions: [session],
            settings: settings,
            diagnostics: diagnostics,
            to: rootDirectoryURL
        )
        let manifestData = try Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        let sessionsData = try Data(contentsOf: exportURL.appendingPathComponent("sessions.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sessions = try decoder.decode([TranscriptSession].self, from: sessionsData)
        let settingsData = try Data(contentsOf: exportURL.appendingPathComponent("settings.json"))
        let writtenSettings = try decoder.decode(PrivacyDataExportSettingsSnapshot.self, from: settingsData)
        let diagnosticsData = try Data(contentsOf: exportURL.appendingPathComponent("diagnostics.json"))
        let writtenDiagnostics = try decoder.decode(PrivacyDataExportDiagnosticsSnapshot.self, from: diagnosticsData)

        XCTAssertEqual(manifest?["includesSecrets"] as? Bool, false)
        XCTAssertEqual(manifest?["sessionCount"] as? Int, 1)
        XCTAssertEqual(sessions, [session])
        XCTAssertEqual(writtenSettings.gitHubRepositoryOwner, "deffenda")
        XCTAssertEqual(writtenSettings.jiraProjectKey, "UCAP")
        XCTAssertEqual(writtenDiagnostics.recentTelemetryEvents.count, 1)
        let combinedText = String(data: manifestData + sessionsData + settingsData + diagnosticsData, encoding: .utf8) ?? ""
        XCTAssertFalse(combinedText.contains("github_pat_secret"))
        XCTAssertFalse(combinedText.contains("jira-secret"))
        XCTAssertFalse(combinedText.contains("apiKey"))
    }

    func testLocalPrivacyDataManagerClearsDiagnosticsTelemetryAndSupportFiles() async throws {
        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-LocalPrivacyDataManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let telemetryURL = rootDirectoryURL.appendingPathComponent("operational-telemetry.jsonl")
        let diagnosticsURL = rootDirectoryURL.appendingPathComponent("recent-log.json")
        let recoveredRecordingsURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        let exportReceiptsURL = rootDirectoryURL.appendingPathComponent("export-receipts.json")

        try FileManager.default.createDirectory(at: recoveredRecordingsURL, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: recoveredRecordingsURL.appendingPathComponent("recovered.m4a"))
        try Data("receipts".utf8).write(to: exportReceiptsURL)

        let telemetryRecorder = OperationalTelemetryRecorder(storageURL: telemetryURL)
        telemetryRecorder.record("recording_started", metadata: ["has_openai_key": "yes"])

        let diagnosticsStore = DiagnosticsLogStore(storageURL: diagnosticsURL)
        await diagnosticsStore.record(
            DiagnosticsLogEntry(
                level: .info,
                category: .settings,
                event: "privacy_data_exported",
                message: "Exported a privacy bundle.",
                metadata: [:]
            )
        )

        let manager = LocalPrivacyDataManager(
            fileManager: .default,
            appSupportURL: rootDirectoryURL,
            telemetryRecorder: telemetryRecorder,
            diagnosticsStore: diagnosticsStore
        )

        await manager.clearLocalSupportArtifacts()

        XCTAssertFalse(FileManager.default.fileExists(atPath: telemetryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: diagnosticsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredRecordingsURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportReceiptsURL.path))
    }
}
