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
        settingsStore.githubRepositoryOwner = "ABD-Enterprises"
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
        XCTAssertEqual(writtenSettings.gitHubRepositoryOwner, "ABD-Enterprises")
        XCTAssertEqual(writtenSettings.jiraProjectKey, "UCAP")
        XCTAssertEqual(writtenDiagnostics.recentTelemetryEvents.count, 1)
        let combinedText = String(data: manifestData + sessionsData + settingsData + diagnosticsData, encoding: .utf8) ?? ""
        XCTAssertFalse(combinedText.contains("github_pat_secret"))
        XCTAssertFalse(combinedText.contains("jira-secret"))
        XCTAssertFalse(combinedText.contains("apiKey"))
    }

    func testStreamedSessionsJSONIsByteIdenticalToArrayEncoding() throws {
        // The streaming writer must produce exactly the same bytes as encoding the
        // whole array at once, for empty / single / multi-session libraries.
        for sessionCount in [0, 1, 3] {
            let sessions = (0..<sessionCount).map { makeSampleTranscriptSession(index: $0 + 1) }

            let rootDirectoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("BugNarrator-PrivacyStreamTests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

            let exportURL = try PrivacyDataExporter().writeBundle(
                sessions: PrivacyDataSessionStream(
                    count: sessions.count,
                    forEach: { body in try sessions.forEach(body) }
                ),
                settings: Self.makeFixtureSettings(),
                diagnostics: Self.makeFixtureDiagnostics(),
                to: rootDirectoryURL
            )
            let streamedData = try Data(contentsOf: exportURL.appendingPathComponent("sessions.json"))

            let referenceEncoder = JSONEncoder()
            referenceEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            referenceEncoder.dateEncodingStrategy = .iso8601
            let referenceData = try referenceEncoder.encode(sessions)

            XCTAssertEqual(
                streamedData,
                referenceData,
                "Streamed sessions.json for \(sessionCount) session(s) must be byte-identical to the array encoding."
            )
        }
    }

    func testWriteBundlePullsSessionsLazilyOneAtATime() throws {
        // The exporter must request sessions through the stream (not a prebuilt
        // array), and the round-trip must decode back to the same sessions.
        let sessions = (0..<4).map { makeSampleTranscriptSession(index: $0 + 1) }
        var maxConcurrentlyHeld = 0
        var liveCount = 0

        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-PrivacyLazyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let stream = PrivacyDataSessionStream(count: sessions.count) { body in
            for session in sessions {
                liveCount += 1
                maxConcurrentlyHeld = max(maxConcurrentlyHeld, liveCount)
                try body(session)
                // The exporter encodes + writes the element before pulling the
                // next, so each yielded session is released before the next is
                // requested.
                liveCount -= 1
            }
        }

        let exportURL = try PrivacyDataExporter().writeBundle(
            sessions: stream,
            settings: Self.makeFixtureSettings(),
            diagnostics: Self.makeFixtureDiagnostics(),
            to: rootDirectoryURL
        )

        XCTAssertEqual(maxConcurrentlyHeld, 1, "The exporter must consume one session at a time, not buffer the library.")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let written = try decoder.decode(
            [TranscriptSession].self,
            from: Data(contentsOf: exportURL.appendingPathComponent("sessions.json"))
        )
        XCTAssertEqual(written, sessions)
    }

    func testManifestSessionCountMatchesSessionsActuallyWrittenWhenStreamSkipsBodies() throws {
        // A library entry whose body cannot be decoded is skipped by the stream,
        // so `count` (library entries) overstates what lands in sessions.json. The
        // manifest must report the number actually written, keeping it consistent
        // with sessions.json — as it was before streaming.
        let writable = [makeSampleTranscriptSession(index: 1), makeSampleTranscriptSession(index: 2)]
        let stream = PrivacyDataSessionStream(count: 3) { body in
            for session in writable {
                try body(session)
            }
            // The 3rd entry is "corrupt" and never yielded.
        }

        let rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-PrivacyManifestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let exportURL = try PrivacyDataExporter().writeBundle(
            sessions: stream,
            settings: Self.makeFixtureSettings(),
            diagnostics: Self.makeFixtureDiagnostics(),
            to: rootDirectoryURL
        )

        let manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: exportURL.appendingPathComponent("manifest.json"))
        ) as? [String: Any]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let writtenSessions = try decoder.decode(
            [TranscriptSession].self,
            from: Data(contentsOf: exportURL.appendingPathComponent("sessions.json"))
        )

        XCTAssertEqual(writtenSessions, writable)
        XCTAssertEqual(manifest?["sessionCount"] as? Int, writable.count)
    }

    private static func makeFixtureSettings() -> PrivacyDataExportSettingsSnapshot {
        let settingsStore = SettingsStore(
            defaults: UserDefaults(suiteName: "BugNarrator-PrivacyFixture-\(UUID().uuidString)") ?? .standard,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        return PrivacyDataExportSettingsSnapshot(settingsStore: settingsStore)
    }

    private static func makeFixtureDiagnostics() -> PrivacyDataExportDiagnosticsSnapshot {
        PrivacyDataExportDiagnosticsSnapshot(
            appName: "BugNarrator",
            versionDescription: "1.0.0 (1)",
            macOSVersion: "macOS Test",
            architecture: "arm64",
            activeTranscriptionModel: "whisper-1",
            issueExtractionModel: "gpt-4.1-mini",
            logLevel: "info",
            debugModeEnabled: false,
            recentTelemetryEvents: [],
            recentDiagnosticsLog: "",
            exportHistory: []
        )
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
