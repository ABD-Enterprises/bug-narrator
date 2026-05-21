import Foundation

@MainActor
final class PostTranscriptionPipelineController {
    private let settingsStore: SettingsStore
    private let sessionLibrary: SessionLibraryController
    private let issueExtractionController: IssueExtractionController
    private let recordingSessionController: RecordingSessionController
    private let statusPresenter: PostTranscriptionStatusPresenter
    private let telemetryRecorder: any OperationalTelemetryRecording
    private let transcriptionLogger: DiagnosticsLogger

    init(
        settingsStore: SettingsStore,
        sessionLibrary: SessionLibraryController,
        issueExtractionController: IssueExtractionController,
        recordingSessionController: RecordingSessionController,
        statusPresenter: PostTranscriptionStatusPresenter,
        telemetryRecorder: any OperationalTelemetryRecording,
        transcriptionLogger: DiagnosticsLogger = DiagnosticsLogger(category: .transcription)
    ) {
        self.settingsStore = settingsStore
        self.sessionLibrary = sessionLibrary
        self.issueExtractionController = issueExtractionController
        self.recordingSessionController = recordingSessionController
        self.statusPresenter = statusPresenter
        self.telemetryRecorder = telemetryRecorder
        self.transcriptionLogger = transcriptionLogger
    }

    func complete(
        session: TranscriptSession,
        apiKey: String,
        mode: PostTranscriptionPipelineMode
    ) async -> PostTranscriptionPipelineResult {
        var session = session
        recordCompletedTranscriptionIfNeeded(session, mode: mode)
        statusPresenter.presentSavingProgress(mode: mode)

        do {
            try persistInitialPostTranscriptionSession(session, mode: mode)
        } catch {
            return .persistenceFailure(session: session, error: error)
        }

        finalizeInitialPostTranscriptionPersistence(session, mode: mode)

        guard settingsStore.autoExtractIssues else {
            return .success(session)
        }

        do {
            session = try await extractIssuesAfterTranscription(for: session, apiKey: apiKey)
            return .success(session)
        } catch {
            return .postTranscriptionFailure(error)
        }
    }

    private func recordCompletedTranscriptionIfNeeded(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) {
        guard mode.recordsCompletionTelemetry else {
            return
        }

        transcriptionLogger.info(
            .transcriptionCompleted,
            "BugNarrator finished transcription and created a transcript session.",
            metadata: [
                "session_id": session.id.uuidString,
                "marker_count": "\(session.markerCount)",
                "screenshot_count": "\(session.screenshotCount)"
            ]
        )
        telemetryRecorder.record(
            .transcriptionCompleted,
            metadata: [
                "marker_count": "\(session.markerCount)",
                "screenshot_count": "\(session.screenshotCount)",
                "model": session.model
            ]
        )
    }

    private func persistInitialPostTranscriptionSession(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) throws {
        switch mode {
        case .finishedRecording:
            try sessionLibrary.persistCompletedTranscript(
                session,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
        case .retry:
            try sessionLibrary.persistUpdatedSession(
                session,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
        }
    }

    private func finalizeInitialPostTranscriptionPersistence(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) {
        guard mode == .finishedRecording else {
            return
        }

        sessionLibrary.setCurrentTranscript(session)
        recordingSessionController.clearActiveRecordingSession()
        statusPresenter.presentTranscriptWindow()
    }

    private func extractIssuesAfterTranscription(
        for session: TranscriptSession,
        apiKey: String
    ) async throws -> TranscriptSession {
        var session = session
        statusPresenter.presentIssueExtractionProgress()
        recordingSessionController.swapActivity(reason: "Extracting review issues")

        let extraction = try await issueExtractionController.extractIssues(
            for: session,
            apiKey: apiKey,
            model: settingsStore.issueExtractionModelValue,
            apiBaseURL: settingsStore.openAIBaseURLValue,
            completionLog: .postTranscription
        )
        session.issueExtraction = extraction
        return session
    }
}

@MainActor
final class FinishedRecordingPostTranscriptionResultHandler {
    private let sessionLibrary: SessionLibraryController
    private let recordingSessionController: RecordingSessionController
    private let statusPresenter: PostTranscriptionStatusPresenter
    private let transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter
    private let postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter
    private let autoCopyTranscript: () -> Bool
    private let cleanupPendingRecordedAudio: () -> Void

    init(
        sessionLibrary: SessionLibraryController,
        recordingSessionController: RecordingSessionController,
        statusPresenter: PostTranscriptionStatusPresenter,
        transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter,
        postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter,
        autoCopyTranscript: @escaping () -> Bool,
        cleanupPendingRecordedAudio: @escaping () -> Void
    ) {
        self.sessionLibrary = sessionLibrary
        self.recordingSessionController = recordingSessionController
        self.statusPresenter = statusPresenter
        self.transcriptPersistenceFailurePresenter = transcriptPersistenceFailurePresenter
        self.postTranscriptionFailurePresenter = postTranscriptionFailurePresenter
        self.autoCopyTranscript = autoCopyTranscript
        self.cleanupPendingRecordedAudio = cleanupPendingRecordedAudio
    }

    func handle(_ result: PostTranscriptionPipelineResult) {
        switch result {
        case .success:
            cleanupPendingRecordedAudio()
            recordingSessionController.endActivity()
            statusPresenter.presentSuccess()

        case .persistenceFailure(let session, let error):
            handleCompletedTranscriptPersistenceFailure(error, session: session)

        case .postTranscriptionFailure(let error):
            cleanupPendingRecordedAudio()
            recordingSessionController.endActivity()
            postTranscriptionFailurePresenter.present(error, operation: .postTranscription)
        }
    }

    private func handleCompletedTranscriptPersistenceFailure(
        _ error: Error,
        session: TranscriptSession
    ) {
        sessionLibrary.stageCurrentTranscript(
            session,
            autoCopyTranscript: autoCopyTranscript()
        )
        recordingSessionController.clearActiveRecordingSession()

        cleanupPendingRecordedAudio()
        recordingSessionController.endActivity()

        transcriptPersistenceFailurePresenter.present(error, sessionID: session.id)
    }
}

@MainActor
final class RetryPostTranscriptionResultHandler {
    private let transcriptionRecovery: TranscriptionRecoveryController
    private let recordingSessionController: RecordingSessionController
    private let statusPresenter: PostTranscriptionStatusPresenter
    private let sessionLibraryStatusPresenter: SessionLibraryStatusPresenter
    private let postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter
    private let debugMode: () -> Bool

    init(
        transcriptionRecovery: TranscriptionRecoveryController,
        recordingSessionController: RecordingSessionController,
        statusPresenter: PostTranscriptionStatusPresenter,
        sessionLibraryStatusPresenter: SessionLibraryStatusPresenter,
        postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter,
        debugMode: @escaping () -> Bool
    ) {
        self.transcriptionRecovery = transcriptionRecovery
        self.recordingSessionController = recordingSessionController
        self.statusPresenter = statusPresenter
        self.sessionLibraryStatusPresenter = sessionLibraryStatusPresenter
        self.postTranscriptionFailurePresenter = postTranscriptionFailurePresenter
        self.debugMode = debugMode
    }

    func handle(
        _ result: PostTranscriptionPipelineResult,
        context: PendingTranscriptionRetryContext
    ) {
        switch result {
        case .success:
            cleanupPreservedRetryAudio(for: context)
            transcriptionRecovery.finishRetry()
            statusPresenter.presentTranscriptWindow()
            recordingSessionController.endActivity()
            statusPresenter.presentSuccess()

        case .persistenceFailure(_, let error):
            transcriptionRecovery.finishRetry()
            recordingSessionController.endActivity()
            sessionLibraryStatusPresenter.presentFailure(error)

        case .postTranscriptionFailure(let error):
            cleanupPreservedRetryAudio(for: context)
            transcriptionRecovery.finishRetry()
            recordingSessionController.endActivity()
            postTranscriptionFailurePresenter.present(error, operation: .retryTranscription)
        }
    }

    private func cleanupPreservedRetryAudio(for context: PendingTranscriptionRetryContext) {
        transcriptionRecovery.cleanupPreservedRetryAudioIfNeeded(
            at: context.audioFileURL,
            debugMode: debugMode()
        )
    }
}
