import Foundation

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
