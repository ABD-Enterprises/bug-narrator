import Foundation

@MainActor
final class PendingTranscriptionRetryFailureHandler {
    private let transcriptionRecovery: TranscriptionRecoveryController
    private let recordingSessionController: RecordingSessionController
    private let retryStatusPresenter: RetryTranscriptionStatusPresenter
    private let provider: () -> AIProvider

    init(
        transcriptionRecovery: TranscriptionRecoveryController,
        recordingSessionController: RecordingSessionController,
        retryStatusPresenter: RetryTranscriptionStatusPresenter,
        provider: @escaping () -> AIProvider
    ) {
        self.transcriptionRecovery = transcriptionRecovery
        self.recordingSessionController = recordingSessionController
        self.retryStatusPresenter = retryStatusPresenter
        self.provider = provider
    }

    func handle(_ error: Error, context: PendingTranscriptionRetryContext) {
        recordingSessionController.endActivity()

        guard let retryFailure = transcriptionRecovery.recordRetryableFailure(
            error,
            context: context,
            provider: provider()
        ) else {
            transcriptionRecovery.finishRetry()
            retryStatusPresenter.presentFailure(error)
            return
        }

        retryStatusPresenter.presentRetryableFailure(retryFailure)
    }
}
