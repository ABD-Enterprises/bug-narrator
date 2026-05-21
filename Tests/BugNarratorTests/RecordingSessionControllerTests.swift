import XCTest
@testable import BugNarrator

@MainActor
final class RecordingSessionControllerTests: XCTestCase {
    func testStartSessionCreatesDraftAndStartsRecorder() async throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        let outcome = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        )

        guard case .started(let recordingSession) = outcome else {
            return XCTFail("Expected started outcome.")
        }
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
        XCTAssertEqual(harness.controller.activeRecordingSession?.sessionID, recordingSession.sessionID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingSession.artifactsDirectoryURL.path))
        XCTAssertEqual(harness.artifactsService.createdDirectories, [recordingSession.artifactsDirectoryURL])
    }

    func testStartSessionRestoresExistingDraftWithoutStartingDuplicateRecorder() async throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        guard case .started(let firstSession) = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        ) else {
            return XCTFail("Expected first start to succeed.")
        }

        let outcome = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        )

        guard case .restored(let restoredSession) = outcome else {
            return XCTFail("Expected restored outcome.")
        }
        XCTAssertEqual(restoredSession.sessionID, firstSession.sessionID)
        XCTAssertEqual(harness.audioRecorder.startCallCount, 1)
    }

    func testStartStatusPresenterSetsRecordingStatusAndTelemetryForStartedSession() {
        let harness = makeStartStatusPresenter()
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/bug-narrator-started-session", isDirectory: true)
        )

        harness.presenter.present(.started(recordingSession))

        XCTAssertEqual(harness.presentationState.status, .recording(harness.recordingMessage))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.count, 1)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "recording_started")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata, harness.diagnosticsMetadata)
    }

    func testStartStatusPresenterSetsRecordingStatusForRestoredSession() {
        let harness = makeStartStatusPresenter(status: .idle("Ready."))
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/bug-narrator-restored-session", isDirectory: true)
        )

        harness.presenter.present(.restored(recordingSession))

        XCTAssertEqual(harness.presentationState.status, .recording(harness.recordingMessage))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testStartStatusPresenterPresentsPreflightFailure() {
        let harness = makeStartStatusPresenter()
        let expectedError = AppError.microphonePermissionDenied

        harness.presenter.present(.preflightFailure(expectedError))

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "recording_start")
    }

    func testStartStatusPresenterNormalizesGenericStartFailure() {
        let harness = makeStartStatusPresenter()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Recorder unavailable"]
        )
        let expectedError = AppError.recordingFailure("Recorder unavailable")

        harness.presenter.present(.failure(error))

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "recording_start")
    }

    func testStartStatusPresenterLeavesStatusForTransitionInProgress() {
        let harness = makeStartStatusPresenter(status: .idle("Ready."))

        harness.presenter.present(.transitionInProgress)

        XCTAssertEqual(harness.presentationState.status, .idle("Ready."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testStartStatusPresenterLeavesStatusForBusyApp() {
        let harness = makeStartStatusPresenter(status: .transcribing("Uploading..."))

        harness.presenter.present(.busy)

        XCTAssertEqual(harness.presentationState.status, .transcribing("Uploading..."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testStopSessionReturnsRecordedAudioAndStoresHandoff() async throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "recorded-stop")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        guard case .started = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        ) else {
            return XCTFail("Expected start to succeed.")
        }

        guard case .ready = harness.controller.beginStoppingSession(statusPhase: .recording) else {
            return XCTFail("Expected stop readiness.")
        }
        let stoppedAudio = try await harness.controller.stopRecording()
        harness.controller.finishStoppingSession()

        XCTAssertEqual(stoppedAudio.fileURL, recordedAudio.fileURL)
        XCTAssertEqual(harness.controller.pendingRecordedAudioSnapshot?.fileURL, recordedAudio.fileURL)
        XCTAssertEqual(harness.audioRecorder.stopCallCount, 1)
        XCTAssertNotNil(harness.controller.activeRecordingSession)
    }

    func testStopWhenIdleReturnsNoActiveRecordingNoOp() throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        let readiness = harness.controller.beginStoppingSession(statusPhase: .idle)

        guard case .noActiveRecording = readiness else {
            return XCTFail("Expected no active recording no-op.")
        }
        XCTAssertEqual(harness.audioRecorder.stopCallCount, 0)
    }

    func testStopReadinessPresenterReturnsReadySession() {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let presenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            )
        )
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/bug-narrator-ready-session", isDirectory: true)
        )

        let readySession = presenter.recordingSession(for: .ready(recordingSession))

        XCTAssertEqual(readySession?.sessionID, recordingSession.sessionID)
        XCTAssertEqual(readySession?.artifactsDirectoryURL, recordingSession.artifactsDirectoryURL)
        XCTAssertEqual(presentationState.status, .recording("Recording in progress."))
        XCTAssertNil(presentationState.currentError)
        XCTAssertTrue(telemetryRecorder.recordedEvents.isEmpty)
    }

    func testStopReadinessPresenterLeavesStatusForTransitionInProgress() {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let presenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: MockOperationalTelemetryRecorder()
            )
        )

        XCTAssertNil(presenter.recordingSession(for: .transitionInProgress))
        XCTAssertEqual(presentationState.status, .recording("Recording in progress."))
        XCTAssertNil(presentationState.currentError)
    }

    func testStopReadinessPresenterLeavesStatusForNoActiveRecording() {
        let presentationState = AppPresentationState(status: .idle("Ready."))
        let presenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: MockOperationalTelemetryRecorder()
            )
        )

        XCTAssertNil(presenter.recordingSession(for: .noActiveRecording))
        XCTAssertEqual(presentationState.status, .idle("Ready."))
        XCTAssertNil(presentationState.currentError)
    }

    func testStopReadinessPresenterPresentsMissingMetadataError() {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let presenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            )
        )
        let expectedError = AppError.recordingFailure("The recording session metadata was unavailable.")

        XCTAssertNil(presenter.recordingSession(for: .missingSessionMetadata))
        XCTAssertEqual(presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(presentationState.currentError, expectedError)
        XCTAssertEqual(telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(telemetryRecorder.recordedEvents.first?.metadata["operation"], "recording_stop")
    }

    func testStopFailurePresenterNormalizesRecordingStopFailure() {
        let harness = makeStopFailurePresenter()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Recorder stop failed"]
        )
        let expectedError = AppError.recordingFailure("Recorder stop failed")

        harness.presenter.presentRecordingStopFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "recording_stop")
    }

    func testStopFailurePresenterNormalizesTranscriptionFailure() {
        let harness = makeStopFailurePresenter()
        let error = NSError(
            domain: "BugNarratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Upload failed"]
        )
        let expectedError = AppError.transcriptionFailure("Upload failed")

        harness.presenter.presentTranscriptionFailure(error)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "transcription")
    }

    func testStopFailurePresenterPresentsPreservationFailure() {
        let harness = makeStopFailurePresenter()
        let expectedError = AppError.recordingFailure("Preserving the recording failed.")

        harness.presenter.presentPreservationFailure(expectedError)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.name, "app_error")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.first?.metadata["operation"], "recording_stop")
    }

    func testStopFailurePresenterOpensSettingsForCredentialFailure() {
        let harness = makeStopFailurePresenter()
        let expectedError = AppError.missingAPIKey

        harness.presenter.presentTranscriptionFailure(expectedError)

        XCTAssertEqual(harness.presentationState.status, .error(expectedError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, expectedError)
        XCTAssertEqual(harness.showSettingsCallCount(), 1)
    }

    func testCancelSessionCancelsRecorderAndRemovesArtifacts() async throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        guard case .started(let recordingSession) = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        ) else {
            return XCTFail("Expected start to succeed.")
        }

        let outcome = await harness.controller.cancelSession(preserveFile: false, onCancelWillBegin: {})

        guard case .cancelled(let cancelledSession) = outcome else {
            return XCTFail("Expected cancelled outcome.")
        }
        XCTAssertEqual(cancelledSession?.sessionID, recordingSession.sessionID)
        XCTAssertNil(harness.controller.activeRecordingSession)
        XCTAssertNil(harness.controller.pendingRecordedAudioSnapshot)
        XCTAssertEqual(harness.audioRecorder.cancelPreserveArguments, [false])
        XCTAssertEqual(harness.artifactsService.removedDirectories, [recordingSession.artifactsDirectoryURL])
    }

    func testCancelStatusPresenterSetsDiscardedStatusForCancelledSession() {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let presenter = RecordingSessionCancelStatusPresenter { status in
            presentationState.setStatus(status, error: nil)
        }

        presenter.present(
            .cancelled(
                RecordingSessionDraft(
                    sessionID: UUID(),
                    artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/bug-narrator-session", isDirectory: true)
                )
            )
        )

        XCTAssertEqual(presentationState.status, .idle("Session discarded."))
        XCTAssertNil(presentationState.currentError)
    }

    func testCancelStatusPresenterLeavesStatusForTransitionInProgress() {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let presenter = RecordingSessionCancelStatusPresenter { status in
            presentationState.setStatus(status, error: nil)
        }

        presenter.present(.transitionInProgress)

        XCTAssertEqual(presentationState.status, .recording("Recording in progress."))
        XCTAssertNil(presentationState.currentError)
    }

    func testCleanupPendingRecordedAudioPreservesDebugFilesUntilExplicitCleanup() async throws {
        let harness = try RecordingSessionControllerHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "pending-audio")
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        guard case .started = await harness.controller.startSession(
            statusPhase: .idle,
            activityReason: "Recording test session"
        ) else {
            return XCTFail("Expected start to succeed.")
        }
        guard case .ready = harness.controller.beginStoppingSession(statusPhase: .recording) else {
            return XCTFail("Expected stop readiness.")
        }
        _ = try await harness.controller.stopRecording()
        harness.controller.finishStoppingSession()

        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        harness.controller.cleanupPendingRecordedAudioIfNeeded(debugMode: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertNil(harness.controller.pendingRecordedAudioSnapshot)
    }

    private func makeStopFailurePresenter() -> (
        presenter: RecordingSessionStopFailurePresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder,
        showSettingsCallCount: () -> Int
    ) {
        let presentationState = AppPresentationState(status: .recording("Recording in progress."))
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        var showSettingsCallCount = 0
        let presenter = RecordingSessionStopFailurePresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            ),
            showSettingsWindow: {
                showSettingsCallCount += 1
            }
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder,
            showSettingsCallCount: { showSettingsCallCount }
        )
    }

    private func makeStartStatusPresenter(
        status: AppStatus = .idle()
    ) -> (
        presenter: RecordingSessionStartStatusPresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder,
        recordingMessage: String,
        diagnosticsMetadata: [String: String]
    ) {
        let presentationState = AppPresentationState(status: status)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let statusMessages = RecordingStatusMessageProvider {
            RecordingStatusMessageSnapshot(
                audioSource: .microphone,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil,
                autoExtractIssues: false,
                autoCopyTranscript: false
            )
        }
        let diagnosticsMetadata = [
            "audio_source": RecordingAudioSource.microphone.diagnosticsValue,
            "has_ai_provider_credential": "yes",
            "ai_provider": "openAI"
        ]
        let presenter = RecordingSessionStartStatusPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            ),
            recordingStatusMessages: statusMessages,
            startDiagnosticsMetadata: { diagnosticsMetadata },
            telemetryRecorder: telemetryRecorder
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder,
            recordingMessage: statusMessages.recordingDetailMessage(),
            diagnosticsMetadata: diagnosticsMetadata
        )
    }
}

@MainActor
private final class RecordingSessionControllerHarness {
    let rootDirectoryURL: URL
    let audioRecorder: MockAudioRecorder
    let artifactsService: MockArtifactsService
    let controller: RecordingSessionController

    init() throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorRecordingSessionControllerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        audioRecorder = MockAudioRecorder()
        artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        controller = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            artifactsService: artifactsService,
            recordingTimer: RecordingTimerViewModel()
        )
    }

    func makeRecordedAudio(fileName: String, contents: String = "audio") throws -> RecordedAudio {
        let fileURL = rootDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("m4a")
        try Data(contents.utf8).write(to: fileURL)
        return RecordedAudio(fileURL: fileURL, duration: 3)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
