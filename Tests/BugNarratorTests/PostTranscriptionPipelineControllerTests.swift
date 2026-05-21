import XCTest
@testable import BugNarrator

@MainActor
final class PostTranscriptionPipelineControllerTests: XCTestCase {
    func testFinishedRecordingSuccessPersistsSessionRecordsTelemetryAndClearsActiveRecording() async throws {
        let harness = try PostTranscriptionPipelineControllerHarness()
        defer { harness.cleanup() }

        let session = makePipelineSession(
            index: 1,
            markers: [
                SessionMarker(
                    index: 1,
                    elapsedTime: 1,
                    title: "Marker 1",
                    screenshotID: nil
                )
            ]
        )
        let recordingSession = RecordingSessionDraft(
            sessionID: session.id,
            artifactsDirectoryURL: harness.rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        harness.recordingSessionController.updateActiveRecordingSession(recordingSession)

        let result = await harness.controller.complete(
            session: session,
            apiKey: "api-key",
            mode: .finishedRecording
        )

        guard case .success(let completedSession) = result else {
            return XCTFail("Expected success result.")
        }
        XCTAssertEqual(completedSession.id, session.id)
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.transcript, session.transcript)
        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)
        XCTAssertNil(harness.recordingSessionController.activeRecordingSession)
        XCTAssertTrue(harness.transcriptWindowSpy.didShow)
        XCTAssertEqual(harness.presentationState.status.phase, .transcribing)
        XCTAssertEqual(harness.presentationState.status.detail, "Step 2 of 2: Saving the finished session locally...")
        XCTAssertEqual(harness.telemetryRecorder.recordedEvents.map(\.name), ["transcription_completed"])
    }

    func testRetrySuccessPersistsUpdatedSessionWithoutFinishedRecordingSideEffects() async throws {
        let harness = try PostTranscriptionPipelineControllerHarness()
        defer { harness.cleanup() }

        let originalSession = makeSampleTranscriptSession(index: 2)
        try harness.transcriptStore.add(originalSession)
        let recoveredSession = makePipelineSession(
            id: originalSession.id,
            index: 2,
            transcript: "Recovered transcript"
        )
        let recordingSession = RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: harness.rootDirectoryURL.appendingPathComponent("active", isDirectory: true)
        )
        harness.recordingSessionController.updateActiveRecordingSession(recordingSession)

        let result = await harness.controller.complete(
            session: recoveredSession,
            apiKey: "api-key",
            mode: .retry
        )

        guard case .success(let completedSession) = result else {
            return XCTFail("Expected success result.")
        }
        XCTAssertEqual(completedSession.transcript, "Recovered transcript")
        XCTAssertEqual(harness.transcriptStore.session(with: originalSession.id)?.transcript, "Recovered transcript")
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.sessionID, recordingSession.sessionID)
        XCTAssertFalse(harness.transcriptWindowSpy.didShow)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testPersistenceFailureReturnsSessionAndDoesNotFinalizeFinishedRecording() async throws {
        let harness = try PostTranscriptionPipelineControllerHarness(failSessionPersistence: true)
        defer { harness.cleanup() }

        let session = makeSampleTranscriptSession(index: 3)
        let recordingSession = RecordingSessionDraft(
            sessionID: session.id,
            artifactsDirectoryURL: harness.rootDirectoryURL.appendingPathComponent("active", isDirectory: true)
        )
        harness.recordingSessionController.updateActiveRecordingSession(recordingSession)

        let result = await harness.controller.complete(
            session: session,
            apiKey: "api-key",
            mode: .finishedRecording
        )

        guard case .persistenceFailure(let failedSession, let error) = result else {
            return XCTFail("Expected persistence failure result.")
        }
        XCTAssertEqual(failedSession.id, session.id)
        XCTAssertTrue(error is AppError)
        XCTAssertNil(harness.sessionLibrary.currentTranscript)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.sessionID, session.id)
        XCTAssertFalse(harness.transcriptWindowSpy.didShow)
    }

    func testAutomaticIssueExtractionSuccessReturnsSessionWithExtractedIssues() async throws {
        let issueExtractionService = MockIssueExtractionService()
        let harness = try PostTranscriptionPipelineControllerHarness(
            autoExtractIssues: true,
            issueExtractionService: issueExtractionService
        )
        defer { harness.cleanup() }
        let issue = ExtractedIssue(
            title: "Save button fails",
            category: .bug,
            summary: "The save button fails.",
            evidenceExcerpt: "Save fails",
            timestamp: 1,
            requiresReview: true
        )
        await issueExtractionService.setResult(
            IssueExtractionResult(summary: "One issue.", issues: [issue])
        )

        let session = makeSampleTranscriptSession(index: 4)

        let result = await harness.controller.complete(
            session: session,
            apiKey: "api-key",
            mode: .finishedRecording
        )

        guard case .success(let completedSession) = result else {
            return XCTFail("Expected success result.")
        }
        XCTAssertEqual(completedSession.issueExtraction?.summary, "One issue.")
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.issueExtraction?.issues.first?.title, "Save button fails")
        XCTAssertEqual(harness.presentationState.status.detail, "Step 3 of 3: Extracting reviewable issues...")
    }

    func testAutomaticIssueExtractionFailureReturnsPostTranscriptionFailure() async throws {
        let issueExtractionService = FailingIssueExtractionService(error: AppError.issueExtractionFailure("Extraction failed."))
        let harness = try PostTranscriptionPipelineControllerHarness(
            autoExtractIssues: true,
            issueExtractionService: issueExtractionService
        )
        defer { harness.cleanup() }

        let session = makeSampleTranscriptSession(index: 5)

        let result = await harness.controller.complete(
            session: session,
            apiKey: "api-key",
            mode: .finishedRecording
        )

        guard case .postTranscriptionFailure(let error) = result else {
            return XCTFail("Expected post-transcription failure result.")
        }
        XCTAssertEqual(error as? AppError, .issueExtractionFailure("Extraction failed."))
        XCTAssertNil(harness.transcriptStore.session(with: session.id)?.issueExtraction)
        XCTAssertEqual(harness.presentationState.status.detail, "Step 3 of 3: Extracting reviewable issues...")
    }
}

@MainActor
private final class PostTranscriptionPipelineControllerHarness {
    let rootDirectoryURL: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let sessionLibrary: SessionLibraryController
    let recordingSessionController: RecordingSessionController
    let presentationState: AppPresentationState
    let telemetryRecorder: MockOperationalTelemetryRecorder
    let transcriptWindowSpy: TranscriptWindowSpy
    let controller: PostTranscriptionPipelineController

    init(
        autoExtractIssues: Bool = false,
        failSessionPersistence: Bool = false,
        issueExtractionService: (any IssueExtracting)? = nil
    ) throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("PostTranscriptionPipelineControllerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        defaultsSuiteName = "PostTranscriptionPipelineControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        settingsStore = SettingsStore(
            defaults: defaults,
            keychainService: MockKeychainService(),
            launchAtLoginService: MockLaunchAtLoginService()
        )
        settingsStore.apiKey = "api-key"
        settingsStore.autoCopyTranscript = true
        settingsStore.autoExtractIssues = autoExtractIssues

        let sessionDataProtector: any SessionDataProtecting = failSessionPersistence
            ? FailingSessionDataProtector()
            : PlaintextSessionDataProtector()
        transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"),
            sessionDataProtector: sessionDataProtector
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts")),
            clipboardService: MockClipboardService()
        )
        let audioRecorder = MockAudioRecorder()
        recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            artifactsService: MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("recording-artifacts")),
            recordingTimer: RecordingTimerViewModel()
        )
        presentationState = AppPresentationState()
        telemetryRecorder = MockOperationalTelemetryRecorder()
        transcriptWindowSpy = TranscriptWindowSpy()

        let recordingStatusMessages = RecordingStatusMessageProvider {
            RecordingStatusMessageSnapshot(
                audioSource: .microphone,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil,
                autoExtractIssues: autoExtractIssues,
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
        let issueExtractionController = IssueExtractionController(
            sessionLibrary: sessionLibrary,
            issueExtractionService: issueExtractionService ?? MockIssueExtractionService()
        )
        controller = PostTranscriptionPipelineController(
            settingsStore: settingsStore,
            sessionLibrary: sessionLibrary,
            issueExtractionController: issueExtractionController,
            recordingSessionController: recordingSessionController,
            statusPresenter: statusPresenter,
            telemetryRecorder: telemetryRecorder
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

@MainActor
private final class TranscriptWindowSpy {
    var didShow = false
}

private struct FailingSessionDataProtector: SessionDataProtecting {
    let writesEncryptedPayloads = false

    func protect(_ data: Data) throws -> Data {
        throw AppError.storageFailure("Injected persistence failure.")
    }

    func unprotect(_ data: Data) throws -> Data {
        data
    }
}

private actor FailingIssueExtractionService: IssueExtracting {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExtractionResult {
        throw error
    }
}

private func makePipelineSession(
    id: UUID = UUID(),
    index: Int,
    transcript: String? = nil,
    markers: [SessionMarker] = []
) -> TranscriptSession {
    TranscriptSession(
        id: id,
        createdAt: Date(timeIntervalSince1970: TimeInterval(index * 60)),
        transcript: transcript ?? "Transcript \(index)",
        duration: TimeInterval(index),
        model: "whisper-1",
        languageHint: nil,
        prompt: nil,
        markers: markers
    )
}
