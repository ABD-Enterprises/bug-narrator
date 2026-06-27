import XCTest
@testable import BugNarrator

@MainActor
final class RetryPostTranscriptionResultHandlerTests: XCTestCase {
    func testSuccessCleansPreservedAudioFinishesRetryAndPresentsSuccess() throws {
        let harness = try RetryPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(index: 1)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        harness.handler.handle(.success(makeSampleTranscriptSession(index: 1)), context: context)

        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.audioFileURL.path))
        XCTAssertTrue(harness.transcriptWindowSpy.didShow)
        XCTAssertEqual(harness.presentationState.status.phase, .success)
        XCTAssertEqual(harness.presentationState.status.detail, "Session saved. Transcript copied to the clipboard.")
    }

    func testSuccessKeepsPreservedAudioWhenRetriedTranscriptStillHasQualityFindings() throws {
        let harness = try RetryPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(index: 5)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        let lowQualitySession = TranscriptSession(
            id: context.session.id,
            createdAt: context.session.createdAt,
            transcript: "same same same same",
            duration: 4,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            transcriptQualityFindings: [
                TranscriptQualityFinding(kind: .boilerplateText, severity: .error, message: "Boilerplate text detected.")
            ]
        )

        harness.handler.handle(.success(lowQualitySession), context: context)

        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        // The preserved recording is kept so the user can retry transcription again.
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.audioFileURL.path))
        XCTAssertEqual(harness.presentationState.status.phase, .success)
    }

    func testSuccessKeepsPreservedAudioWhenDebugModeIsEnabled() throws {
        let harness = try RetryPostTranscriptionResultHandlerHarness(debugMode: true)
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(index: 2)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        harness.handler.handle(.success(makeSampleTranscriptSession(index: 2)), context: context)

        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.audioFileURL.path))
        XCTAssertTrue(harness.transcriptWindowSpy.didShow)
        XCTAssertEqual(harness.presentationState.status.phase, .success)
    }

    func testPersistenceFailureFinishesRetryAndKeepsPreservedAudio() throws {
        let harness = try RetryPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(index: 3)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))
        harness.recordingSessionController.beginActivity(reason: "Retry post-transcription")
        XCTAssertTrue(harness.recordingSessionController.hasActiveProcessActivity)

        harness.handler.handle(
            .persistenceFailure(session: context.session, error: AppError.storageFailure("Disk full.")),
            context: context
        )

        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertFalse(
            harness.recordingSessionController.hasActiveProcessActivity,
            "Retry persistence failure must end the process activity."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.audioFileURL.path))
        XCTAssertFalse(harness.transcriptWindowSpy.didShow)
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .storageFailure("Disk full."))
    }

    func testPostTranscriptionFailureCleansPreservedAudioFinishesRetryAndPresentsFailure() throws {
        let harness = try RetryPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let context = try harness.makeRetryContext(index: 4)

        XCTAssertTrue(harness.transcriptionRecovery.beginRetry(for: context.session.id))

        harness.handler.handle(.postTranscriptionFailure(AppError.invalidAPIKey), context: context)

        XCTAssertNil(harness.transcriptionRecovery.retryingSessionID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.audioFileURL.path))
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .invalidAPIKey)
        XCTAssertTrue(harness.settingsWindowSpy.didShow)
    }
}

@MainActor
private final class RetryPostTranscriptionResultHandlerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let sessionLibrary: SessionLibraryController
    let recordingSessionController: RecordingSessionController
    let transcriptionRecovery: TranscriptionRecoveryController
    let presentationState: AppPresentationState
    let transcriptWindowSpy = RetryTranscriptWindowSpy()
    let settingsWindowSpy = RetrySettingsWindowSpy()
    let handler: RetryPostTranscriptionResultHandler

    init(debugMode: Bool = false) throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("RetryPostTranscriptionResultHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"),
            sessionDataProtector: PlaintextSessionDataProtector()
        )
        let sessionArtifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("session-artifacts", isDirectory: true)
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: sessionArtifactsService,
            clipboardService: MockClipboardService()
        )
        recordingSessionController = RecordingSessionController(
            audioRecorder: MockAudioRecorder(),
            microphonePermissionService: MicrophonePermissionService(permissionAccess: MockAudioRecorder()),
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("recording-artifacts")),
            recordingTimer: RecordingTimerViewModel()
        )
        transcriptionRecovery = TranscriptionRecoveryController(
            sessionLibrary: sessionLibrary,
            artifactsService: sessionArtifactsService
        )
        presentationState = AppPresentationState()
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: MockOperationalTelemetryRecorder()
        )
        let recordingStatusMessages = RecordingStatusMessageProvider {
            RecordingStatusMessageSnapshot(
                audioSource: .microphone,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil,
                autoExtractIssues: false,
                autoCopyTranscript: true
            )
        }
        let statusPresenter = PostTranscriptionStatusPresenter(
            recordingStatusMessages: recordingStatusMessages,
            setStatus: { [presentationState] status in
                presentationState.setStatus(status, error: nil)
            },
            showTranscriptWindow: { [transcriptWindowSpy] in
                transcriptWindowSpy.didShow = true
            }
        )
        let sessionLibraryStatusPresenter = SessionLibraryStatusPresenter(errorPresenter: errorPresenter)
        let postTranscriptionFailurePresenter = PostTranscriptionFailurePresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { [settingsWindowSpy] in
                settingsWindowSpy.didShow = true
            }
        )
        handler = RetryPostTranscriptionResultHandler(
            transcriptionRecovery: transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            statusPresenter: statusPresenter,
            sessionLibraryStatusPresenter: sessionLibraryStatusPresenter,
            postTranscriptionFailurePresenter: postTranscriptionFailurePresenter,
            debugMode: { debugMode }
        )
    }

    func makeRetryContext(index: Int) throws -> PendingTranscriptionRetryContext {
        let sessionID = UUID()
        let artifactsDirectoryURL = rootDirectoryURL
            .appendingPathComponent("retry-session-\(index)", isDirectory: true)
        try FileManager.default.createDirectory(at: artifactsDirectoryURL, withIntermediateDirectories: true)
        let audioFileURL = artifactsDirectoryURL.appendingPathComponent("recording.m4a")
        try Data("audio".utf8).write(to: audioFileURL)
        let pendingTranscription = PendingTranscription(
            audioFileName: audioFileURL.lastPathComponent,
            failureReason: .missingAPIKey,
            preservedAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
        let session = TranscriptSession(
            id: sessionID,
            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
            transcript: "",
            duration: 4,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: pendingTranscription,
            artifactsDirectoryPath: artifactsDirectoryURL.path
        )
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
private final class RetryTranscriptWindowSpy {
    var didShow = false
}

@MainActor
private final class RetrySettingsWindowSpy {
    var didShow = false
}
