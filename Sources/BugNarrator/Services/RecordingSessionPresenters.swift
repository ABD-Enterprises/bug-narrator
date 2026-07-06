import Combine
import Foundation

@MainActor
final class RecordingSessionStartStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let recordingStatusMessages: RecordingStatusMessageProvider
    private let startDiagnosticsMetadata: () -> [String: String]
    private let telemetryRecorder: any OperationalTelemetryRecording
    var showSettingsWindow: () -> Void
    var prepareErrorPresentationSideEffects: () -> Void
    private let recordingLogger: DiagnosticsLogger
    private let permissionsLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        recordingStatusMessages: RecordingStatusMessageProvider,
        startDiagnosticsMetadata: @escaping () -> [String: String],
        telemetryRecorder: any OperationalTelemetryRecording,
        showSettingsWindow: @escaping () -> Void = {},
        prepareErrorPresentationSideEffects: @escaping () -> Void = {},
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording),
        permissionsLogger: DiagnosticsLogger = DiagnosticsLogger(category: .permissions)
    ) {
        self.errorPresenter = errorPresenter
        self.recordingStatusMessages = recordingStatusMessages
        self.startDiagnosticsMetadata = startDiagnosticsMetadata
        self.telemetryRecorder = telemetryRecorder
        self.showSettingsWindow = showSettingsWindow
        self.prepareErrorPresentationSideEffects = prepareErrorPresentationSideEffects
        self.recordingLogger = recordingLogger
        self.permissionsLogger = permissionsLogger
    }

    func present(_ outcome: RecordingSessionStartOutcome) {
        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStartIgnored, "The start request was ignored because another recording transition is already in progress.")

        case .busy:
            recordingLogger.warning(.sessionStartRejected, "The start request was rejected because BugNarrator is already busy.")

        case .restored(let recordingSession):
            recordingLogger.warning(
                "session_start_reconciled_active_session",
                "A start request arrived while a recording session draft was still active; restoring recording state instead of starting a duplicate recorder.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            errorPresenter.setStatus(.recording(recordingStatusMessages.recordingDetailMessage()))

        case .preflightFailure(let preflightError):
            permissionsLogger.warning(.sessionStartPreflightFailed, preflightError.userMessage)
            prepareErrorPresentationSideEffects()
            let result = errorPresenter.presentError(preflightError, operation: .recordingStart)
            if result.shouldOpenSettingsWindow {
                showSettingsWindow()
            }

        case .failure(let error):
            prepareErrorPresentationSideEffects()
            let result = errorPresenter.presentError(
                error,
                operation: .recordingStart,
                fallback: { .recordingFailure($0) }
            )
            if result.shouldOpenSettingsWindow {
                showSettingsWindow()
            }

        case .started(let recordingSession):
            errorPresenter.setStatus(.recording(recordingStatusMessages.recordingDetailMessage()))
            let metadata = startDiagnosticsMetadata()
            var logMetadata = metadata
            logMetadata["session_id"] = recordingSession.sessionID.uuidString
            recordingLogger.info(
                .sessionStarted,
                "A feedback session started successfully.",
                metadata: logMetadata
            )
            telemetryRecorder.record(.recordingStarted, metadata: metadata)
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

