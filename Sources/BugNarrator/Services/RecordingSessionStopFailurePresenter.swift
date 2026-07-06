import Combine
import Foundation

@MainActor
final class RecordingSessionStopFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func presentRecordingStopFailure(_ error: Error) {
        present(error, operation: .recordingStop, fallback: { .recordingFailure($0) })
    }

    func presentTranscriptionFailure(_ error: Error) {
        present(error, operation: .transcription)
    }

    func presentPreservationFailure(_ error: Error) {
        present(error, operation: .recordingStop)
    }

    private func present(
        _ error: Error,
        operation: AppErrorOperation,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        let result = errorPresenter.presentError(error, operation: operation, fallback: fallback)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}
