import Foundation

@MainActor
final class PostTranscriptionFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func present(
        _ error: Error,
        operation: AppErrorOperation = .postTranscription
    ) {
        let result = errorPresenter.presentPostTranscriptionError(error, operation: operation)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

