import Foundation

@MainActor
final class ScreenshotCaptureController {
    var prepareForScreenshotSelection: (() -> Void)?
    var restoreAfterScreenshotSelection: (() -> Void)?

    private let screenshotCoordinator: ScreenshotCoordinator
    private let recordingSessionController: RecordingSessionController
    private let errorPresenter: AppErrorPresenter
    private let statusPhase: () -> AppStatus.Phase
    private let elapsedDuration: () -> TimeInterval
    private let recordingDetailMessage: () -> String
    private let setStatus: (AppStatus, AppError?) -> Void
    private let showToast: (String, TransientToastStyle) -> Void
    private let logger: DiagnosticsLogger

    init(
        screenshotCoordinator: ScreenshotCoordinator,
        recordingSessionController: RecordingSessionController,
        errorPresenter: AppErrorPresenter,
        statusPhase: @escaping () -> AppStatus.Phase,
        elapsedDuration: @escaping () -> TimeInterval,
        recordingDetailMessage: @escaping () -> String,
        setStatus: @escaping (AppStatus, AppError?) -> Void,
        showToast: @escaping (String, TransientToastStyle) -> Void,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .screenshots)
    ) {
        self.screenshotCoordinator = screenshotCoordinator
        self.recordingSessionController = recordingSessionController
        self.errorPresenter = errorPresenter
        self.statusPhase = statusPhase
        self.elapsedDuration = elapsedDuration
        self.recordingDetailMessage = recordingDetailMessage
        self.setStatus = setStatus
        self.showToast = showToast
        self.logger = logger
    }

    var isCaptureInProgress: Bool {
        screenshotCoordinator.isCaptureInProgress
    }

    func captureScreenshot() async {
        guard statusPhase() == .recording,
              let recordingSession = recordingSessionController.activeRecordingSession else {
            let error = AppError.noActiveSession("Start a feedback session before capturing a screenshot.")
            logger.warning("screenshot_rejected_no_session", error.userMessage)
            setStatus(.error(error.userMessage), error)
            return
        }

        if isCaptureInProgress {
            let error = AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
            logger.warning("screenshot_rejected_busy", error.userMessage)
            setStatus(.recording(error.userMessage), error)
            return
        }

        let screenshotIndex = recordingSession.screenshots.count + 1
        let markerIndex = recordingSession.markers.count + 1
        let elapsedTime = max(recordingSessionController.currentDuration, elapsedDuration())
        let markerID = UUID()
        let markerTitle = "Screenshot \(screenshotIndex)"

        do {
            let captureResult = try await screenshotCoordinator.captureScreenshot(
                in: recordingSession,
                prefix: "capture",
                index: screenshotIndex,
                elapsedTime: elapsedTime,
                associatedMarkerID: markerID,
                onSelectionWillBegin: { [weak self] in
                    self?.setStatus(.recording("Drag to select a screenshot region. Press Esc to cancel."), nil)
                    self?.prepareForScreenshotSelection?()
                },
                onSelectionDidEnd: { [weak self] in
                    self?.restoreAfterScreenshotSelection?()
                },
                isSessionActive: { [weak self] sessionID in
                    guard let self else {
                        return false
                    }

                    return statusPhase() == .recording
                        && recordingSessionController.activeRecordingSession?.sessionID == sessionID
                }
            )
            guard case let .captured(screenshot) = captureResult else {
                guard statusPhase() == .recording,
                      recordingSessionController.activeRecordingSession?.sessionID == recordingSession.sessionID else {
                    return
                }

                setStatus(.recording(recordingDetailMessage()), nil)
                showToast("Screenshot canceled", .informational)
                return
            }
            guard statusPhase() == .recording,
                  var latestRecordingSession = recordingSessionController.activeRecordingSession,
                  latestRecordingSession.sessionID == recordingSession.sessionID else {
                return
            }
            latestRecordingSession.markers.append(
                SessionMarker(
                    id: markerID,
                    index: markerIndex,
                    elapsedTime: elapsedTime,
                    title: markerTitle,
                    note: nil,
                    screenshotID: screenshot.id
                )
            )
            latestRecordingSession.screenshots.append(screenshot)
            recordingSessionController.updateActiveRecordingSession(latestRecordingSession)
            logger.info(
                "screenshot_captured",
                "Captured a screenshot and inserted the automatic marker.",
                metadata: [
                    "session_id": recordingSession.sessionID.uuidString,
                    "screenshot_index": "\(screenshotIndex)",
                    "marker_index": "\(markerIndex)"
                ]
            )
            setStatus(.recording("Captured \(markerTitle)."), nil)
            showToast("Screenshot captured", .success)
        } catch {
            let normalizedError = errorPresenter.normalizeError(
                error,
                operation: .screenshotCapture,
                fallback: { .screenshotCaptureFailure($0) }
            )
            let appError = normalizedError.appError
            guard statusPhase() == .recording else {
                return
            }

            errorPresenter.logAppError(normalizedError, context: "screenshot_capture_failed")
            var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "screenshot_capture_failed")
            metadata["session_id"] = recordingSession.sessionID.uuidString
            logger.error(
                "screenshot_capture_failed",
                appError.userMessage,
                metadata: metadata
            )
            setStatus(.recording(appError.userMessage), appError)
        }
    }

    func cancelPendingSelection(reason: String) {
        screenshotCoordinator.cancelPendingSelection(reason: reason)
    }
}
