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

