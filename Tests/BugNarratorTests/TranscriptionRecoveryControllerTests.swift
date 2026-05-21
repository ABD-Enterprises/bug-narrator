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
            provider: .openAI,
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
            provider: .openAI,
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

    func testRetryContextRejectsLegacyCrashRecoverySessions() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let session = try harness.addPendingSession(failureReason: .crashRecovery)

        let resolution = harness.controller.retryContext(
            for: session.id,
            isRecording: false,
            provider: .openAI,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: nil
        )

        guard case .failure(let appError, let opensSettings, let statusMessage) = resolution else {
            return XCTFail("Expected crash recovery failure.")
        }
        XCTAssertEqual(
            appError,
            .transcriptionFailure("Unexpected-quit recording recovery is no longer supported. Delete this session and start a new recording.")
        )
        XCTAssertFalse(opensSettings)
        XCTAssertEqual(
            statusMessage,
            "Unexpected-quit recording recovery is no longer supported. Delete this session and start a new recording."
        )
    }

    func testPreservationPresenterPresentsPreservedSessionRecoveryStatus() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }
        let session = try harness.addPendingSession(failureReason: .missingAPIKey)
        let presentationState = AppPresentationState()
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
        var showTranscriptCallCount = 0
        var showSettingsCallCount = 0
        let presenter = RetryableSessionPreservationPresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { showTranscriptCallCount += 1 },
            showSettingsWindow: { showSettingsCallCount += 1 },
            provider: { .openAI }
        )

        presenter.presentPreservedSession(session, appError: .missingAPIKey)

        XCTAssertEqual(presentationState.status, .error(try XCTUnwrap(session.transcriptionRecoveryMessage)))
        XCTAssertEqual(presentationState.currentError, .missingAPIKey)
        XCTAssertEqual(showTranscriptCallCount, 1)
        XCTAssertEqual(showSettingsCallCount, 1)

        let telemetry = try XCTUnwrap(
            telemetryRecorder.recordedEvents.last { $0.name == TelemetryEvent.appError.rawValue }
        )
        XCTAssertEqual(telemetry.metadata["context"], "preserve_retryable_session")
        XCTAssertEqual(telemetry.metadata["operation"], "transcription")
        XCTAssertEqual(telemetry.metadata["error_type"], "missing_api_key")
    }

    func testPreservationPresenterPresentsPersistenceFailureRecoveryStatus() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }
        let session = try harness.addPendingSession(failureReason: .missingAPIKey)
        let presentationState = AppPresentationState()
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
        var showTranscriptCallCount = 0
        var showSettingsCallCount = 0
        let presenter = RetryableSessionPreservationPresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { showTranscriptCallCount += 1 },
            showSettingsWindow: { showSettingsCallCount += 1 },
            provider: { .openAI }
        )
        let underlyingError = NSError(
            domain: "TranscriptionRecoveryControllerTests",
            code: 17,
            userInfo: [NSLocalizedDescriptionKey: "Index path is a directory"]
        )

        presenter.presentPersistenceFailure(
            underlyingError,
            retryableSession: session,
            recoveryAppError: .missingAPIKey
        )

        let appError = AppError.storageFailure("Index path is a directory")
        XCTAssertEqual(presentationState.status, .error("Recording preserved, but \(appError.userMessage)"))
        XCTAssertEqual(presentationState.currentError, appError)
        XCTAssertEqual(showTranscriptCallCount, 1)
        XCTAssertEqual(showSettingsCallCount, 1)

        let telemetry = try XCTUnwrap(
            telemetryRecorder.recordedEvents.last { $0.name == TelemetryEvent.appError.rawValue }
        )
        XCTAssertEqual(telemetry.metadata["context"], "retryable_session_persist_failed")
        XCTAssertEqual(telemetry.metadata["operation"], "session_library")
        XCTAssertEqual(telemetry.metadata["error_type"], "storage_failure")
        XCTAssertEqual(telemetry.metadata["underlying_error"], "Index path is a directory")
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

    func testPreserveRetryableSessionKeepsSamePathAudioAndStoresPendingSession() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        let audioURL = recordingSession.artifactsDirectoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension("m4a")
        let recordedAudio = try harness.makeRecordedAudio(fileURL: audioURL, contents: "audio")

        let result = harness.controller.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: harness.request,
            failureReason: .invalidAPIKey
        )

        guard case .preserved(let session, _) = result else {
            return XCTFail("Expected retryable session preservation.")
        }
        XCTAssertEqual(session.pendingTranscriptionAudioURL?.standardizedFileURL, audioURL.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: audioURL, encoding: .utf8), "audio")
        XCTAssertTrue(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testPreserveRetryableSessionRejectsEmptySamePathAudio() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        let audioURL = recordingSession.artifactsDirectoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension("m4a")
        let recordedAudio = try harness.makeRecordedAudio(fileURL: audioURL, contents: "")

        let result = harness.controller.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: harness.request,
            failureReason: .invalidAPIKey
        )

        guard case .preservationFailure(let error as AppError) = result else {
            return XCTFail("Expected empty preserved audio to fail preservation.")
        }
        XCTAssertEqual(error, .recordingFailure("The preserved audio file was empty."))
        XCTAssertNil(harness.transcriptStore.session(with: recordingSession.sessionID))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testPreserveRetryableSessionRemovesEmptyCopiedPreservedAudio() throws {
        let harness = try TranscriptionRecoveryControllerHarness()
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        let recordedAudio = try harness.makeRecordedAudio(fileName: "empty-source", contents: "")

        let result = harness.controller.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: harness.request,
            failureReason: .invalidAPIKey
        )

        guard case .preservationFailure(let error as AppError) = result else {
            return XCTFail("Expected empty preserved audio to fail preservation.")
        }
        XCTAssertEqual(error, .recordingFailure("The preserved audio file was empty."))

        let preservedAudioURL = recordingSession.artifactsDirectoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension("m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: preservedAudioURL.path))
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
            provider: .openAI,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: nil
        ) else {
            return XCTFail("Expected ready retry context.")
        }
        XCTAssertTrue(harness.controller.beginRetry(for: session.id))

        let failure = try XCTUnwrap(
            harness.controller.recordRetryableFailure(AppError.invalidAPIKey, context: context, provider: .openAI)
        )

        XCTAssertNil(harness.controller.retryingSessionID)
        XCTAssertEqual(failure.appError, .invalidAPIKey)
        XCTAssertEqual(harness.transcriptStore.session(with: session.id)?.pendingTranscription?.attemptCount, 3)
        XCTAssertTrue(failure.statusMessage.contains("retried 3 times"))
    }

    func testRecordRetryableFailureLogsPersistenceErrorWhenIndexCannotBeSaved() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetryPersistLog-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let diagnosticsStore = DiagnosticsLogStore(storageURL: storeURL)
        defer { try? FileManager.default.removeItem(at: storeURL) }
        let transcriptionLogger = DiagnosticsLogger(category: .transcription, store: diagnosticsStore)

        let harness = try TranscriptionRecoveryControllerHarness(transcriptionLogger: transcriptionLogger)
        defer { harness.cleanup() }

        let session = try harness.addPendingSession(failureReason: .missingAPIKey, attemptCount: 1)
        guard case .ready(let context) = harness.controller.retryContext(
            for: session.id,
            isRecording: false,
            provider: .openAI,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: nil
        ) else {
            return XCTFail("Expected ready retry context.")
        }
        XCTAssertTrue(harness.controller.beginRetry(for: session.id))

        let indexURL = harness.rootDirectoryURL.appendingPathComponent("sessions.index.json")
        try? FileManager.default.removeItem(at: indexURL)
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)

        let failure = try XCTUnwrap(
            harness.controller.recordRetryableFailure(AppError.invalidAPIKey, context: context, provider: .openAI)
        )

        XCTAssertEqual(failure.appError, .invalidAPIKey)
        XCTAssertNil(harness.controller.retryingSessionID)
        XCTAssertEqual(harness.sessionLibrary.currentTranscript?.id, session.id)

        try? await Task.sleep(nanoseconds: 200_000_000)
        let entries = await diagnosticsStore.recentEntries()
        let entry = try XCTUnwrap(
            entries.first { $0.event == "transcription_retry_state_persist_failed" }
        )
        XCTAssertEqual(entry.metadata["session_id"], session.id.uuidString)
        XCTAssertEqual(entry.metadata["failure_reason"], PendingTranscriptionFailureReason.invalidAPIKey.rawValue)
        XCTAssertEqual(entry.metadata["attempt_count"], "2")
        XCTAssertNotNil(entry.metadata["underlying_error"])
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

    init(transcriptionLogger: DiagnosticsLogger? = nil) throws {
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
        if let transcriptionLogger {
            controller = TranscriptionRecoveryController(
                sessionLibrary: sessionLibrary,
                artifactsService: artifactsService,
                transcriptionLogger: transcriptionLogger
            )
        } else {
            controller = TranscriptionRecoveryController(
                sessionLibrary: sessionLibrary,
                artifactsService: artifactsService
            )
        }
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
        return try makeRecordedAudio(fileURL: fileURL, contents: contents)
    }

    func makeRecordedAudio(fileURL: URL, contents: String) throws -> RecordedAudio {
        try Data(contents.utf8).write(to: fileURL)
        return RecordedAudio(fileURL: fileURL, duration: 3)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
