import XCTest
@testable import BugNarrator

@MainActor
final class LocalDataDeletionControllerTests: XCTestCase {
    func testDeleteAllLocalDataClearsPrivacyArtifactsWhenNoSessionsExist() async throws {
        let harness = LocalDataDeletionControllerHarness()
        defer { harness.cleanup() }

        let outcome = try await harness.controller.deleteAllLocalData(currentTranscript: nil)

        XCTAssertEqual(outcome.deletedSessionCount, 0)
        XCTAssertEqual(outcome.statusMessage, "Cleared local diagnostics and export history.")
        XCTAssertEqual(harness.localPrivacyDataManager.clearCallCount, 1)
    }

    func testDeleteAllLocalDataDeletesOneStoredSession() async throws {
        let harness = LocalDataDeletionControllerHarness()
        defer { harness.cleanup() }
        let session = harness.makeSession()
        try harness.transcriptStore.add(session)
        harness.sessionLibrary.stageCurrentTranscript(session)

        let outcome = try await harness.controller.deleteAllLocalData(currentTranscript: harness.sessionLibrary.currentTranscript)

        XCTAssertEqual(outcome.deletedSessionCount, 1)
        XCTAssertEqual(outcome.statusMessage, "Deleted 1 local session and cleared local diagnostics.")
        XCTAssertTrue(harness.transcriptStore.sessions.isEmpty)
        XCTAssertNil(harness.sessionLibrary.currentTranscript)
        XCTAssertEqual(harness.localPrivacyDataManager.clearCallCount, 1)
    }

    func testDeleteAllLocalDataDeletesStoredAndUnsavedCurrentSessions() async throws {
        let harness = LocalDataDeletionControllerHarness()
        defer { harness.cleanup() }
        let storedSession = harness.makeSession()
        let unsavedSession = harness.makeSession()
        try harness.transcriptStore.add(storedSession)
        harness.sessionLibrary.stageCurrentTranscript(unsavedSession)

        let outcome = try await harness.controller.deleteAllLocalData(currentTranscript: harness.sessionLibrary.currentTranscript)

        XCTAssertEqual(outcome.deletedSessionCount, 2)
        XCTAssertEqual(outcome.statusMessage, "Deleted 2 local sessions and cleared local diagnostics.")
        XCTAssertTrue(harness.transcriptStore.sessions.isEmpty)
        XCTAssertNil(harness.sessionLibrary.currentTranscript)
        XCTAssertEqual(harness.localPrivacyDataManager.clearCallCount, 1)
    }
}

@MainActor
private final class LocalDataDeletionControllerHarness {
    let rootDirectoryURL: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let transcriptStore: TranscriptStore
    let artifactsService: MockArtifactsService
    let sessionLibrary: SessionLibraryController
    let localPrivacyDataManager: MockLocalPrivacyDataManager
    let controller: LocalDataDeletionController

    init() {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("LocalDataDeletionControllerTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let defaultsSuiteName = "LocalDataDeletionControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let keychainService = MockKeychainService()
        let settingsStore = SettingsStore(
            defaults: defaults,
            keychainService: keychainService,
            launchAtLoginService: MockLaunchAtLoginService()
        )
        let transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        let artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        let sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: MockClipboardService()
        )
        let exportService = MockExportService()
        let exportHistoryController = ExportHistoryController(exportService: exportService)
        let localPrivacyDataManager = MockLocalPrivacyDataManager()
        let supportDataController = SupportDataController(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            exportService: exportService,
            clipboardService: MockClipboardService(),
            debugBundleExporter: MockDebugBundleExporter(),
            privacyDataExporter: MockPrivacyDataExporter(),
            telemetryRecorder: MockOperationalTelemetryRecorder(),
            localPrivacyDataManager: localPrivacyDataManager
        )

        self.rootDirectoryURL = rootDirectoryURL
        self.defaultsSuiteName = defaultsSuiteName
        self.defaults = defaults
        self.transcriptStore = transcriptStore
        self.artifactsService = artifactsService
        self.sessionLibrary = sessionLibrary
        self.localPrivacyDataManager = localPrivacyDataManager
        self.controller = LocalDataDeletionController(
            transcriptStore: transcriptStore,
            sessionLibrary: sessionLibrary,
            supportDataController: supportDataController,
            exportHistoryController: exportHistoryController
        )
    }

    func makeSession() -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(),
            transcript: "A local transcript.",
            duration: 10,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
}
