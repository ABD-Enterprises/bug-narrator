import Foundation

@MainActor
final class IssueExportPresentationController {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func presentPreflightFailure(_ failure: IssueExportPreflightFailure) {
        let result = presentExportError(failure.error)
        if failure.opensSettings || result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }

    func presentReviewPreparation(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.reviewPreparationStatus(destination: destination))
    }

    func presentReviewReady(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.reviewReadyStatus(destination: destination))
    }

    func presentRemoteExportStarted(destination: ExportDestination) {
        errorPresenter.setStatus(IssueExportStatusPresenter.remoteExportStatus(destination: destination))
    }

    func presentCompletion(_ completion: IssueExportCompletion) {
        errorPresenter.setStatus(IssueExportStatusPresenter.completionStatus(completion))
    }

    @discardableResult
    func presentFailure(_ error: Error) -> AppErrorPresentationResult {
        let result = presentExportError(error)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
        return result
    }

    private func presentExportError(_ error: Error) -> AppErrorPresentationResult {
        errorPresenter.presentError(error, operation: .export, fallback: { .exportFailure($0) })
    }
}
