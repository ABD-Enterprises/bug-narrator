import Foundation

@MainActor
final class TranscriptPersistenceFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let sessionLibraryLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.sessionLibraryLogger = sessionLibraryLogger
    }

    func present(_ error: Error, sessionID: UUID) {
        let normalizedError = errorPresenter.normalizeError(
            error,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )
        let appError = normalizedError.appError
        errorPresenter.logAppError(normalizedError, context: "transcript_persist_failed")
        var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "transcript_persist_failed")
        metadata["session_id"] = sessionID.uuidString
        sessionLibraryLogger.error(
            "transcript_persist_failed",
            "Transcription succeeded, but saving the transcript locally failed.",
            metadata: metadata
        )
        errorPresenter.setStatus(
            .error("Transcript ready, but \(appError.userMessage(for: errorPresenter.activeProvider))"),
            error: appError
        )
        showTranscriptWindow()
    }
}
