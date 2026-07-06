import Combine
import Foundation

@MainActor
final class RecordingSessionCancelStatusPresenter {
    static let discardedStatus = AppStatus.idle("Session discarded.")

    private let setStatus: (AppStatus) -> Void
    private let recordingLogger: DiagnosticsLogger

    init(
        setStatus: @escaping (AppStatus) -> Void,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording)
    ) {
        self.setStatus = setStatus
        self.recordingLogger = recordingLogger
    }

    func present(_ outcome: RecordingSessionCancelOutcome) {
        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug("session_cancel_ignored", "The cancel request was ignored because another recording transition is already in progress.")

        case .cancelled(let activeRecordingSession):
            if let activeRecordingSession {
                recordingLogger.info(
                    "session_cancelled",
                    "The active feedback session was discarded.",
                    metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
                )
            }
            setStatus(Self.discardedStatus)
        }
    }
}

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

