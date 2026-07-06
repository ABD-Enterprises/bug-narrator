import Foundation

@MainActor
final class FinishedRecordingPostTranscriptionResultHandler {
    private let sessionLibrary: SessionLibraryController
    private let recordingSessionController: RecordingSessionController
    private let statusPresenter: PostTranscriptionStatusPresenter
    private let transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter
    private let postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter
    private let autoCopyTranscript: () -> Bool
    private let cleanupPendingRecordedAudio: () -> Void
    private let preserveRecordedAudioForReview: (TranscriptSession) -> Void
    private let showSavedSessionReveal: (TranscriptSession) -> Void

    init(
        sessionLibrary: SessionLibraryController,
        recordingSessionController: RecordingSessionController,
        statusPresenter: PostTranscriptionStatusPresenter,
        transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter,
        postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter,
        autoCopyTranscript: @escaping () -> Bool,
        cleanupPendingRecordedAudio: @escaping () -> Void,
        preserveRecordedAudioForReview: @escaping (TranscriptSession) -> Void = { _ in },
        showSavedSessionReveal: @escaping (TranscriptSession) -> Void = { _ in }
    ) {
        self.sessionLibrary = sessionLibrary
        self.recordingSessionController = recordingSessionController
        self.statusPresenter = statusPresenter
        self.transcriptPersistenceFailurePresenter = transcriptPersistenceFailurePresenter
        self.postTranscriptionFailurePresenter = postTranscriptionFailurePresenter
        self.autoCopyTranscript = autoCopyTranscript
        self.cleanupPendingRecordedAudio = cleanupPendingRecordedAudio
        self.preserveRecordedAudioForReview = preserveRecordedAudioForReview
        self.showSavedSessionReveal = showSavedSessionReveal
    }

    func handle(_ result: PostTranscriptionPipelineResult) {
        switch result {
        case .success(let session):
            // A "successful" transcript with high-confidence quality findings is
            // likely unusable; preserve the recording for re-transcription instead
            // of deleting it (#466).
            if session.hasHighConfidenceQualityFindings {
                preserveRecordedAudioForReview(session)
            } else {
                cleanupPendingRecordedAudio()
            }
            recordingSessionController.endActivity()
            statusPresenter.presentSuccess()
            showSavedSessionReveal(session)

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
        case .success(let session):
            // If the retried transcript is still low-quality, keep the preserved
            // recording (already in the session assets dir) for another retry (#466).
            if !session.hasHighConfidenceQualityFindings {
                cleanupPreservedRetryAudio(for: context)
            }
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
