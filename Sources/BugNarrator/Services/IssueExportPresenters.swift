import Foundation

enum IssueExportStatusPresenter {
    static func reviewPreparationStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Checking \(destination.rawValue) for similar open issues...")
    }

    static func reviewReadyStatus(destination: ExportDestination) -> AppStatus {
        .success("Review the similar \(destination.rawValue) issues before export.")
    }

    static func remoteExportStatus(destination: ExportDestination) -> AppStatus {
        .transcribing("Exporting reviewed issues to \(destination.rawValue)...")
    }

    static func completionStatus(_ completion: IssueExportCompletion) -> AppStatus {
        .success(completion.summary)
    }
}

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
