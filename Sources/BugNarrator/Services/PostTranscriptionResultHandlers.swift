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
