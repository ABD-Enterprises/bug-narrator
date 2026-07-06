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
