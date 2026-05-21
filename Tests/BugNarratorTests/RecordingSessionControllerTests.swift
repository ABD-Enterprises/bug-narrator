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
