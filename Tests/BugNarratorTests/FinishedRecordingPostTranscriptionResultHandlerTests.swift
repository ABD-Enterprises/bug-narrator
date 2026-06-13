import XCTest
@testable import BugNarrator

@MainActor
final class FinishedRecordingPostTranscriptionResultHandlerTests: XCTestCase {
    func testSuccessCleansPendingAudioAndPresentsSuccessWithoutShowingTranscriptWindow() async throws {
        let harness = try FinishedRecordingPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let recordedAudio = try harness.makeRecordedAudio()
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        _ = try await harness.recordingSessionController.stopRecording()

        let session = makeSampleTranscriptSession(index: 1)
        harness.handler.handle(.success(session))

        XCTAssertNil(harness.recordingSessionController.pendingRecordedAudioSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertEqual(harness.presentationState.status.phase, .success)
        XCTAssertEqual(harness.presentationState.status.detail, "Session saved. Transcript copied to the clipboard.")
        XCTAssertEqual(harness.revealSpy.sessionIDs, [session.id])
        XCTAssertFalse(harness.transcriptWindowSpy.didShow)
    }

    func testPersistenceFailureStagesTranscriptClearsActiveRecordingAndPresentsFailure() async throws {
        let harness = try FinishedRecordingPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let session = makeSampleTranscriptSession(index: 2)
        let recordedAudio = try harness.makeRecordedAudio()
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        _ = try await harness.recordingSessionController.stopRecording()
        harness.recordingSessionController.updateActiveRecordingSession(
            RecordingSessionDraft(
                sessionID: session.id,
                artifactsDirectoryURL: harness.rootDirectoryURL.appendingPathComponent("active", isDirectory: true)
            )
        )

        harness.handler.handle(.persistenceFailure(session: session, error: AppError.storageFailure("Disk full.")))

        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)
        XCTAssertEqual(harness.sessionLibrary.selectedTranscriptID, session.id)
        XCTAssertNil(harness.recordingSessionController.activeRecordingSession)
        XCTAssertNil(harness.recordingSessionController.pendingRecordedAudioSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .storageFailure("Disk full."))
        XCTAssertTrue(harness.transcriptWindowSpy.didShow)
    }

    func testPostTranscriptionFailureCleansPendingAudioAndPresentsFailure() async throws {
        let harness = try FinishedRecordingPostTranscriptionResultHandlerHarness()
        defer { harness.cleanup() }
        let recordedAudio = try harness.makeRecordedAudio()
        harness.audioRecorder.stopResults = [.success(recordedAudio)]
        _ = try await harness.recordingSessionController.stopRecording()

        harness.handler.handle(.postTranscriptionFailure(AppError.invalidAPIKey))

        XCTAssertNil(harness.recordingSessionController.pendingRecordedAudioSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordedAudio.fileURL.path))
        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(harness.presentationState.currentError, .invalidAPIKey)
        XCTAssertTrue(harness.settingsWindowSpy.didShow)
    }
}

@MainActor
private final class FinishedRecordingPostTranscriptionResultHandlerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let sessionLibrary: SessionLibraryController
    let recordingSessionController: RecordingSessionController
    let audioRecorder: MockAudioRecorder
    let presentationState: AppPresentationState
    let transcriptWindowSpy = TranscriptWindowSpy()
    let settingsWindowSpy = SettingsWindowSpy()
    let revealSpy = SavedSessionRevealSpy()
    let handler: FinishedRecordingPostTranscriptionResultHandler

    init(debugMode: Bool = false) throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("FinishedRecordingPostTranscriptionResultHandlerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"),
            sessionDataProtector: PlaintextSessionDataProtector()
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts")),
            clipboardService: MockClipboardService()
        )
        audioRecorder = MockAudioRecorder()
        recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("recording-artifacts")),
            recordingTimer: RecordingTimerViewModel()
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
        let transcriptPersistenceFailurePresenter = TranscriptPersistenceFailurePresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { [transcriptWindowSpy] in
                transcriptWindowSpy.didShow = true
            }
        )
        let postTranscriptionFailurePresenter = PostTranscriptionFailurePresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { [settingsWindowSpy] in
                settingsWindowSpy.didShow = true
            }
        )
        handler = FinishedRecordingPostTranscriptionResultHandler(
            sessionLibrary: sessionLibrary,
            recordingSessionController: recordingSessionController,
            statusPresenter: statusPresenter,
            transcriptPersistenceFailurePresenter: transcriptPersistenceFailurePresenter,
            postTranscriptionFailurePresenter: postTranscriptionFailurePresenter,
            autoCopyTranscript: { true },
            cleanupPendingRecordedAudio: { [recordingSessionController] in
                recordingSessionController.cleanupPendingRecordedAudioIfNeeded(debugMode: debugMode)
            },
            showSavedSessionReveal: { [revealSpy] session in
                revealSpy.sessionIDs.append(session.id)
            }
        )
    }

    func makeRecordedAudio() throws -> RecordedAudio {
        let fileURL = rootDirectoryURL.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        try Data("audio".utf8).write(to: fileURL)
        return RecordedAudio(fileURL: fileURL, duration: 4)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

@MainActor
private final class TranscriptWindowSpy {
    var didShow = false
}

@MainActor
private final class SettingsWindowSpy {
    var didShow = false
}

@MainActor
private final class SavedSessionRevealSpy {
    var sessionIDs: [UUID] = []
}
