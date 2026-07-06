import Combine
import Foundation

@MainActor
final class RecordingSessionStopReadinessPresenter {
    private let errorPresenter: AppErrorPresenter
    private let recordingLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording)
    ) {
        self.errorPresenter = errorPresenter
        self.recordingLogger = recordingLogger
    }

    func recordingSession(for readiness: RecordingSessionStopReadiness) -> RecordingSessionDraft? {
        switch readiness {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStopIgnored, "The stop request was ignored because another recording transition is already in progress.")
            return nil

        case .noActiveRecording:
            recordingLogger.warning(.sessionStopRejected, "The stop request was rejected because no recording session is active.")
            return nil

        case .missingSessionMetadata:
            _ = errorPresenter.presentError(
                AppError.recordingFailure("The recording session metadata was unavailable."),
                operation: .recordingStop
            )
            return nil

        case .ready(let recordingSession):
            return recordingSession
        }
    }
}
