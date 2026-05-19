import XCTest
@testable import BugNarrator

@MainActor
final class TranscriptionRecoveryControllerTests: XCTestCase {
    func testRetryContextReadyAndRetryStateTracksActiveSession() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let session = try harness.addPendingSession()

        let resolution = harness.controller.retryContext(
            for: session.id,
            isRecording: false,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: nil
        )

        guard case .ready(let context) = resolution else {
            return XCTFail("Expected ready retry context.")
        }
        XCTAssertEqual(context.session.id, session.id)
        XCTAssertTrue(harness.controller.beginRetry(for: session.id))
        XCTAssertEqual(harness.controller.retryingSessionID, session.id)
        XCTAssertFalse(harness.controller.beginRetry(for: UUID()))
        harness.controller.finishRetry()
        XCTAssertNil(harness.controller.retryingSessionID)
    }

    func testRetryContextWithoutCredentialReturnsRecoveryMessage() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let session = try harness.addPendingSession(failureReason: .missingAPIKey)

        let resolution = harness.controller.retryContext(
            for: session.id,
            isRecording: false,
            hasUsableAIProviderCredential: false,
            aiProviderCompatibilityIssue: nil
        )

        guard case .failure(let appError, let opensSettings, let statusMessage) = resolution else {
            return XCTFail("Expected missing credential failure.")
        }
        XCTAssertEqual(appError, .missingAPIKey)
        XCTAssertTrue(opensSettings)
        XCTAssertEqual(statusMessage, session.transcriptionRecoveryMessage)
    }

    func testPreserveRetryableSessionCopiesAudioAndStoresPendingSession() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let recordedAudio = try harness.makeRecordedAudio(fileName: "source", contents: "audio")
        let recordingSession = try harness.makeRecordingSession()

        let result = harness.controller.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: harness.request,
            failureReason: .invalidAPIKey
        )

        guard case .preserved(let session, let appError) = result else {
            return XCTFail("Expected retryable session preservation.")
        }
        XCTAssertEqual(appError, .invalidAPIKey)
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.pendingTranscription?.failureReason, .invalidAPIKey)
        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(session.pendingTranscriptionAudioURL).path))
    }

    func testPreserveRetryableSessionPersistenceFailureStagesCurrentTranscript() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let indexURL = harness.rootDirectoryURL.appendingPathComponent("sessions.index.json")
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)
        let recordedAudio = try harness.makeRecordedAudio(fileName: "source", contents: "audio")
        let recordingSession = try harness.makeRecordingSession()

        let result = harness.controller.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: harness.request,
            failureReason: .missingAPIKey
        )

        guard case .persistenceFailure(let session, _) = result else {
            return XCTFail("Expected persistence failure.")
        }
        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)
        XCTAssertEqual(harness.sessionLibrary.selectedTranscriptID, session.id)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .missingAPIKey)
    }

    func testRecordRetryableFailureIncrementsAttemptCountAndFinishesRetry() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let session = try harness.addPendingSession(failureReason: .missingAPIKey, attemptCount: 2)
        guard case .ready(let context) = harness.controller.retryContext(
            for: session.id,
            isRecording: false,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: nil
        ) else {
            return XCTFail("Expected ready retry context.")
        }
        XCTAssertTrue(harness.controller.beginRetry(for: session.id))

        let failure = try XCTUnwrap(
            harness.controller.recordRetryableFailure(AppError.invalidAPIKey, context: context)
        )

        XCTAssertNil(harness.controller.retryingSessionID)
        XCTAssertEqual(failure.appError, .invalidAPIKey)
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.pendingTranscription?.attemptCount, 3)
        XCTAssertTrue(failure.statusMessage.contains("retried 3 times"))
    }

    func testCleanupPreservedRetryAudioHonorsDebugMode() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let retainedAudio = try harness.makeRecordedAudio(fileName: "retained", contents: "audio")
        harness.controller.cleanupPreservedRetryAudioIfNeeded(at: retainedAudio.fileURL, debugMode: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedAudio.fileURL.path))

        let removedAudio = try harness.makeRecordedAudio(fileName: "removed", contents: "audio")
        harness.controller.cleanupPreservedRetryAudioIfNeeded(at: removedAudio.fileURL, debugMode: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedAudio.fileURL.path))
    }
}

@MainActor
private struct TranscriptionRecoveryControllerHarness {
    let rootDirectoryURL: URL
    let transcriptStore: TranscriptStore
    let artifactsService: MockArtifactsService
    let sessionLibrary: SessionLibraryController
    let controller: TranscriptionRecoveryController
    let request = TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)

    init() throws {
        rootDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TranscriptionRecoveryControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        transcriptStore = TranscriptStore(
            fileManager: .default,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: MockClipboardService()
        )
        controller = TranscriptionRecoveryController(
            sessionLibrary: sessionLibrary,
            artifactsService: artifactsService
        )
    }

    func addPendingSession(
        failureReason: PendingTranscriptionFailureReason = .missingAPIKey,
        attemptCount: Int = 0
    ) throws -> TranscriptSession {
        let recordingSession = try makeRecordingSession()
        let audioURL = recordingSession.artifactsDirectoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension("m4a")
        try Data("audio".utf8).write(to: audioURL)
        let session = TranscriptSession(
            id: recordingSession.sessionID,
            createdAt: Date(),
            transcript: "",
            duration: 3,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: PendingTranscription(
                audioFileName: audioURL.lastPathComponent,
                failureReason: failureReason,
                preservedAt: Date(),
                attemptCount: attemptCount
            ),
            artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
        )
        try transcriptStore.add(session)
        return session
    }

    func makeRecordingSession() throws -> RecordingSessionDraft {
        let sessionID = UUID()
        let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)
        return RecordingSessionDraft(sessionID: sessionID, artifactsDirectoryURL: artifactsDirectoryURL)
    }

    func makeRecordedAudio(fileName: String, contents: String) throws -> RecordedAudio {
        let fileURL = rootDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("m4a")
        try Data(contents.utf8).write(to: fileURL)
        return RecordedAudio(fileURL: fileURL, duration: 3)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
