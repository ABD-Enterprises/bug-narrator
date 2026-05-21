import XCTest
@testable import BugNarrator

@MainActor
final class SupportDataControllerTests: XCTestCase {
    func testCopyDebugInfoCopiesSnapshotToClipboard() {
        let harness = SupportDataControllerHarness()
        defer { harness.cleanup() }
        let sessionID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

        let result = harness.controller.copyDebugInfo(sessionID: sessionID)

        XCTAssertEqual(result.snapshot.sessionID, sessionID)
        XCTAssertEqual(result.statusMessage, "Debug info copied to the clipboard.")
        XCTAssertEqual(harness.clipboardService.copiedStrings.count, 1)
        XCTAssertTrue(harness.clipboardService.copiedStrings[0].contains("Session ID: \(sessionID.uuidString)"))
        XCTAssertFalse(harness.clipboardService.copiedStrings[0].contains(harness.settingsStore.trimmedAPIKey))
    }

    func testExportDebugBundleBuildsSnapshotAndReturnsVerboseStatusWhenDebugModeIsEnabled() async throws {
        let bundleURL = URL(fileURLWithPath: "/tmp/bugnarrator-debug-bundle")
        let harness = SupportDataControllerHarness(debugMode: true)
        defer { harness.cleanup() }
        harness.debugBundleExporter.exportResult = .success(bundleURL)

        let metadata = DebugSessionMetadata.make(
            currentTranscript: nil,
            displayedTranscript: nil,
            activeRecordingSession: nil,
            status: .idle(),
            currentError: nil
        )

        let result = try await harness.controller.exportDebugBundle(sessionMetadata: metadata)

        XCTAssertEqual(result?.bundleURL, bundleURL)
        XCTAssertEqual(result?.statusMessage, "Debug bundle exported with verbose diagnostics.")
        XCTAssertEqual(harness.debugBundleExporter.exportedSnapshots.count, 1)
        XCTAssertEqual(harness.debugBundleExporter.exportedSnapshots[0].sessionMetadata, metadata)
        XCTAssertTrue(harness.debugBundleExporter.exportedSnapshots[0].debugInfo.debugModeEnabled)
    }

    func testExportPrivacyDataIncludesSessionsDiagnosticsAndTelemetry() async throws {
        let bundleURL = URL(fileURLWithPath: "/tmp/bugnarrator-data-export")
        let exportService = MockExportService()
        let harness = SupportDataControllerHarness(exportService: exportService)
        defer { harness.cleanup() }
        harness.privacyDataExporter.exportResult = .success(bundleURL)
        harness.telemetryRecorder.recentEventsResult = [
            OperationalTelemetryEvent(name: "recording_started", metadata: ["source": "test"])
        ]
        let session = harness.makeSession()
        try harness.transcriptStore.add(session)

        let receipt = ExportReceipt(
            fingerprint: "fixture-fingerprint",
            sourceIssueID: UUID(),
            destination: .github,
            targetIdentity: "acme/bugnarrator",
            state: .succeeded,
            remoteIdentifier: "42",
            remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/42"),
            updatedAt: Date()
        )
        await exportService.setExportReceipts([receipt])

        let result = try await harness.controller.exportPrivacyData(exportHistoryFallback: [])

        XCTAssertEqual(result?.bundleURL, bundleURL)
        XCTAssertEqual(
            result?.statusMessage,
            "Data export created. API keys and tracker credentials were not included."
        )
        XCTAssertEqual(harness.privacyDataExporter.exportRequests.count, 1)
        XCTAssertEqual(harness.privacyDataExporter.exportRequests[0].sessions.map(\.id), [session.id])
        XCTAssertEqual(harness.privacyDataExporter.exportRequests[0].diagnostics.recentTelemetryEvents.count, 1)
        XCTAssertEqual(harness.privacyDataExporter.exportRequests[0].diagnostics.exportHistory, [receipt])
        XCTAssertEqual(harness.telemetryRecorder.recentEventsLimits, [200])
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.last?.name, TelemetryEvent.privacyDataExported.rawValue)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.last?.metadata["session_count"], "1")
    }

    func testExportPrivacyDataUsesFallbackExportHistoryWhenRefreshFails() async throws {
        let harness = SupportDataControllerHarness(
            exportService: FailingExportHistoryService()
        )
        defer { harness.cleanup() }
        harness.privacyDataExporter.exportResult = .success(URL(fileURLWithPath: "/tmp/export"))
        let fallbackReceipt = ExportReceipt(
            fingerprint: "fallback",
            sourceIssueID: UUID(),
            destination: .jira,
            targetIdentity: "UCAP",
            state: .pending,
            remoteIdentifier: nil,
            remoteURL: nil,
            updatedAt: Date()
        )

        _ = try await harness.controller.exportPrivacyData(exportHistoryFallback: [fallbackReceipt])

        XCTAssertEqual(harness.privacyDataExporter.exportRequests[0].diagnostics.exportHistory, [fallbackReceipt])
    }

    func testClearLocalPrivacyArtifactsUsesInjectedManager() async {
        let harness = SupportDataControllerHarness()
        defer { harness.cleanup() }

        await harness.controller.clearLocalPrivacyArtifacts()

        XCTAssertEqual(harness.localPrivacyDataManager.clearCallCount, 1)
    }

    func testActionPresenterAppliesStatusesAndRevealsExportedBundles() {
        let harness = SupportDataControllerHarness()
        defer { harness.cleanup() }
        var statuses: [AppStatus] = []
        var revealedURLs: [URL] = []
        var presentedUtilityResults: [AppUtilityActionResult] = []
        let presenter = SupportDataActionPresenter(
            setStatus: { statuses.append($0) },
            revealInFinder: { url in
                revealedURLs.append(url)
                return .opened
            },
            presentUtilityActionResult: { presentedUtilityResults.append($0) }
        )
        let debugBundleURL = URL(fileURLWithPath: "/tmp/bugnarrator-debug-bundle")
        let privacyBundleURL = URL(fileURLWithPath: "/tmp/bugnarrator-privacy-export")

        presenter.presentCopyDebugInfo(harness.controller.copyDebugInfo(sessionID: nil))
        presenter.presentDebugBundleExport(
            DebugBundleExportCompletion(bundleURL: debugBundleURL, statusMessage: "Debug bundle exported.")
        )
        presenter.presentPrivacyDataExport(
            PrivacyDataExportCompletion(
                bundleURL: privacyBundleURL,
                statusMessage: "Data export created. API keys and tracker credentials were not included."
            )
        )
        presenter.presentLocalDataDeletion(LocalDataDeletionOutcome(deletedSessionCount: 2))
        presenter.presentLocalDataDeletion(
            LocalDataDeletionResult.blocked(message: "Stop recording or transcription before deleting local data.")
        )

        XCTAssertEqual(
            statuses,
            [
                .success("Debug info copied to the clipboard."),
                .success("Debug bundle exported."),
                .success("Data export created. API keys and tracker credentials were not included."),
                .success("Deleted 2 local sessions and cleared local diagnostics."),
                .error("Stop recording or transcription before deleting local data.")
            ]
        )
        XCTAssertEqual(revealedURLs, [debugBundleURL, privacyBundleURL])
        XCTAssertEqual(presentedUtilityResults, [.opened, .opened])
    }
}

@MainActor
private final class SupportDataControllerHarness {
    let rootDirectoryURL: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let keychainService: MockKeychainService
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let exportService: any IssueExporting
    let clipboardService: MockClipboardService
    let debugBundleExporter: MockDebugBundleExporter
    let privacyDataExporter: MockPrivacyDataExporter
    let telemetryRecorder: MockOperationalTelemetryRecorder
    let localPrivacyDataManager: MockLocalPrivacyDataManager
    let controller: SupportDataController

    init(
        debugMode: Bool = false,
        exportService: any IssueExporting = MockExportService()
    ) {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("SupportDataControllerTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let defaultsSuiteName = "SupportDataControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let keychainService = MockKeychainService()
        let settingsStore = SettingsStore(
            defaults: defaults,
            keychainService: keychainService,
            launchAtLoginService: MockLaunchAtLoginService()
        )
        settingsStore.apiKey = "test-api-key"
        settingsStore.debugMode = debugMode

        let transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        let clipboardService = MockClipboardService()
        let debugBundleExporter = MockDebugBundleExporter()
        let privacyDataExporter = MockPrivacyDataExporter()
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let localPrivacyDataManager = MockLocalPrivacyDataManager()

        self.rootDirectoryURL = rootDirectoryURL
        self.defaultsSuiteName = defaultsSuiteName
        self.defaults = defaults
        self.keychainService = keychainService
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.exportService = exportService
        self.clipboardService = clipboardService
        self.debugBundleExporter = debugBundleExporter
        self.privacyDataExporter = privacyDataExporter
        self.telemetryRecorder = telemetryRecorder
        self.localPrivacyDataManager = localPrivacyDataManager
        self.controller = SupportDataController(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            exportService: exportService,
            clipboardService: clipboardService,
            debugBundleExporter: debugBundleExporter,
            privacyDataExporter: privacyDataExporter,
            telemetryRecorder: telemetryRecorder,
            localPrivacyDataManager: localPrivacyDataManager
        )
    }

    func makeSession(id: UUID = UUID()) -> TranscriptSession {
        TranscriptSession(
            id: id,
            createdAt: Date(),
            transcript: "A saved transcript.",
            duration: 12,
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

private actor FailingExportHistoryService: IssueExporting {
    func fetchGitHubRepositories(token: String) async throws -> [GitHubRepositoryOption] { [] }

    func fetchJiraProjects(_ configuration: JiraConnectionConfiguration) async throws -> [JiraProjectOption] { [] }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        []
    }

    func validateGitHubConfiguration(_ configuration: GitHubExportConfiguration) async throws {}

    func validateJiraConfiguration(_ configuration: JiraExportConfiguration) async throws {}

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        IssueExportReview(destination: .github, sessionID: session.id, items: [])
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        IssueExportReview(destination: .jira, sessionID: session.id, items: [])
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        []
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        []
    }

    func exportHistory() async throws -> [ExportReceipt] {
        throw NSError(domain: "SupportDataControllerTests", code: 1)
    }
}
