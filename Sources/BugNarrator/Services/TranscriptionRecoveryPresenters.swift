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
final class RetryableSessionPreservationPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let showSettingsWindow: () -> Void
    private let provider: () -> AIProvider
    private let sessionLibraryLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        showSettingsWindow: @escaping () -> Void,
        provider: @escaping () -> AIProvider,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.showSettingsWindow = showSettingsWindow
        self.provider = provider
        self.sessionLibraryLogger = sessionLibraryLogger
    }

    func presentPreservedSession(_ retryableSession: TranscriptSession, appError: AppError) {
        let currentProvider = provider()
        errorPresenter.logAppError(appError, context: "preserve_retryable_session", operation: .transcription)
        errorPresenter.setStatus(
            .error(
                retryableSession.transcriptionRetryMessage(for: currentProvider)
                    ?? appError.userMessage(for: currentProvider)
            ),
            error: appError
        )
        showTranscriptWindow()
        if appError.suggestsProviderSettings(for: currentProvider) {
            showSettingsWindow()
        }
    }

    func presentPersistenceFailure(
        _ error: Error,
        retryableSession: TranscriptSession,
        recoveryAppError: AppError
    ) {
        let currentProvider = provider()
        let normalizedError = errorPresenter.normalizeError(
            error,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )
        let persistenceError = normalizedError.appError
        errorPresenter.logAppError(normalizedError, context: "retryable_session_persist_failed")
        var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "retryable_session_persist_failed")
        metadata["session_id"] = retryableSession.id.uuidString
        sessionLibraryLogger.error(
            "retryable_session_persist_failed",
            "The preserved recording could not be saved into local session history.",
            metadata: metadata
        )
        errorPresenter.setStatus(
            .error("Recording preserved, but \(persistenceError.userMessage(for: currentProvider))"),
            error: persistenceError
        )
        showTranscriptWindow()
        if recoveryAppError.suggestsProviderSettings(for: currentProvider) {
            showSettingsWindow()
        }
    }
}
