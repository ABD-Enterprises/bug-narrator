import Foundation

enum IssueExtractionStatusPresenter {
    static var manualProgressStatus: AppStatus {
        .transcribing("Running issue extraction with a 10-second time limit...")
    }

    static func manualCompletionStatus(issueCount: Int) -> AppStatus {
        .success("Extracted \(issueCount) review issues.")
    }
}

@MainActor
final class ManualIssueExtractionStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let showSettingsWindow: () -> Void
    private let logger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        showSettingsWindow: @escaping () -> Void,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .transcription)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.showSettingsWindow = showSettingsWindow
        self.logger = logger
    }

    func presentRequestStarted(sessionID: UUID) {
        errorPresenter.setStatus(IssueExtractionStatusPresenter.manualProgressStatus)
        logger.info(
            "issue_extraction_requested",
            "Issue extraction was requested for the selected transcript.",
            metadata: ["session_id": sessionID.uuidString]
        )
    }

    func presentCompletion(issueCount: Int) {
        errorPresenter.setStatus(IssueExtractionStatusPresenter.manualCompletionStatus(issueCount: issueCount))
        showTranscriptWindow()
    }

    func presentPreflightFailure(_ error: AppError, sessionID: UUID) {
        logger.warning(
            "issue_extraction_preflight_failed",
            error.userMessage,
            metadata: ["session_id": sessionID.uuidString]
        )
        presentError(error)
    }

    func presentFailure(_ error: Error) {
        presentError(error, fallback: { .issueExtractionFailure($0) })
    }

    private func presentError(
        _ error: Error,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        let result = errorPresenter.presentError(error, operation: .postTranscription, fallback: fallback)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}
