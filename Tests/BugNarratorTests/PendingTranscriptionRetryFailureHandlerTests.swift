import XCTest
@testable import BugNarrator

@MainActor
final class PendingTranscriptionRetryFailureHandlerTests: XCTestCase {
    func testRecoverableFailureUpdatesPendingSessionFinishesRetryAndPresentsRecovery() throws {
        let harness = try PendingTranscriptionRetryFailureHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(attemptCount: 1)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        harness.handler.handle(AppError.invalidAPIKey, context: context)

        let updatedSession = try XCTUnwrap(harness.transcriptStore.session(with: context.session.id))
        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertEqual(updatedSession.pendingTranscription?.failureReason, .invalidAPIKey)
        XCTAssertEqual(updatedSession.pendingTranscription?.attemptCount, 2)
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .invalidAPIKey)
        XCTAssertTrue(harness.transcriptWindowSpy.didShow)
        XCTAssertTrue(harness.settingsWindowSpy.didShow)
    }

    func testNonrecoverableFailureFinishesRetryAndPresentsFailure() throws {
        let harness = try PendingTranscriptionRetryFailureHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext()

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        harness.handler.handle(AppError.transcriptionFailure("Network unavailable."), context: context)

        let storedSession = try XCTUnwrap(harness.transcriptStore.session(with: context.session.id))
        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertEqual(storedSession.pendingTranscription?.failureReason, .missingAPIKey)
        XCTAssertEqual(storedSession.pendingTranscription?.attemptCount, 0)
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .transcriptionFailure("Network unavailable."))
        XCTAssertFalse(harness.transcriptWindowSpy.didShow)
        XCTAssertFalse(harness.settingsWindowSpy.didShow)
    }
}

@MainActor
private final class PendingTranscriptionRetryFailureHandlerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let sessionLibrary: SessionLibraryController
    let recordingSessionController: RecordingSessionController
    let transcriptionRecovery: TranscriptionRecoveryController
    let presentationState: AppPresentationState
    let transcriptWindowSpy = PendingRetryTranscriptWindowSpy()
    let settingsWindowSpy = PendingRetrySettingsWindowSpy()
    let handler: PendingTranscriptionRetryFailureHandler

    init() throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("PendingTranscriptionRetryFailureHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"),
            sessionDataProtector: PlaintextSessionDataProtector()
        )
        let artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: MockClipboardService()
        )
        let audioRecorder = MockAudioRecorder()
        recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            artifactsService: artifactsService,
            recordingTimer: RecordingTimerViewModel()
        )
        transcriptionRecovery = TranscriptionRecoveryController(
            sessionLibrary: sessionLibrary,
            artifactsService: artifactsService
        )
        presentationState = AppPresentationState()
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: MockOperationalTelemetryRecorder()
        )
        let retryStatusPresenter = RetryTranscriptionStatusPresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { [settingsWindowSpy] in
                settingsWindowSpy.didShow = true
            },
            showTranscriptWindow: { [transcriptWindowSpy] in
                transcriptWindowSpy.didShow = true
            }
        )
        handler = PendingTranscriptionRetryFailureHandler(
            transcriptionRecovery: transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            retryStatusPresenter: retryStatusPresenter
        )
    }

    func makeRetryContext(attemptCount: Int = 0) throws -> PendingTranscriptionRetryContext {
        let sessionID = UUID()
        let artifactsDirectoryURL = rootDirectoryURL
            .appendingPathComponent("retry-session-\(sessionID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)
        let audioFileURL = artifactsDirectoryURL.appendingPathComponent("recording.m4a")
        try Data("audio".utf8).write(to: audioFileURL)
        let pendingTranscription = PendingTranscription(
            audioFileName: audioFileURL.lastPathComponent,
            failureReason: .missingAPIKey,
            preservedAt: Date(timeIntervalSince1970: 1),
            attemptCount: attemptCount
        )
        let session = TranscriptSession(
            id: sessionID,
            createdAt: Date(timeIntervalSince1970: 1),
            transcript: "",
            duration: 8,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: pendingTranscription,
            artifactsDirectoryPath: artifactsDirectoryURL.path
        )
        try transcriptStore.add(session)
        return PendingTranscriptionRetryContext(
            session: session,
            pendingTranscription: pendingTranscription,
            audioFileURL: audioFileURL
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

@MainActor
private final class PendingRetryTranscriptWindowSpy {
    var didShow = false
}

@MainActor
private final class PendingRetrySettingsWindowSpy {
    var didShow = false
}
