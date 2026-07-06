import Foundation

@MainActor
final class RetryTranscriptionStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void
    private let showTranscriptWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void,
        showTranscriptWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
        self.showTranscriptWindow = showTranscriptWindow
    }

    func presentRetryStarted(progressMessage: String) {
        errorPresenter.setStatus(.transcribing(progressMessage))
    }

    func presentRetryContextFailure(
        appError: AppError,
        opensSettings: Bool,
        statusMessage: String?
    ) {
        if let statusMessage {
            errorPresenter.setStatus(.error(statusMessage), error: appError)
        } else {
            let result = errorPresenter.presentError(appError, operation: .retryTranscription)
            if result.shouldOpenSettingsWindow {
                showSettingsWindow()
            }
        }

        if opensSettings {
            showSettingsWindow()
        }
    }

    func presentRetryableFailure(_ failure: PendingTranscriptionRetryFailure) {
        errorPresenter.logAppError(
            failure.appError,
            context: "retry_pending_transcription",
            operation: .retryTranscription
        )
        errorPresenter.setStatus(.error(failure.statusMessage), error: failure.appError)
        showTranscriptWindow()
        showSettingsWindow()
    }

    func presentFailure(_ error: Error) {
        let result = errorPresenter.presentError(error, operation: .retryTranscription)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

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
