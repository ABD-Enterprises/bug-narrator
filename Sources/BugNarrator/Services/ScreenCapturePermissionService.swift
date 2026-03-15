import AppKit
import CoreGraphics
import Foundation

@MainActor
struct SystemScreenCapturePermissionAccess: ScreenCapturePermissionAccessing {
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    func currentPermissionState() -> ScreenCapturePermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    func requestPermissionIfNeeded() async -> ScreenCapturePermissionState {
        let initialState = currentPermissionState()
        permissionsLogger.debug(
            "screen_recording_permission_state_read",
            "Read the current Screen Recording permission state.",
            metadata: ["state": initialState.diagnosticsValue]
        )

        switch initialState {
        case .granted:
            permissionsLogger.debug(
                "screen_recording_permission_authorized",
                "Screen Recording access is already available."
            )
            return .granted
        case .notDetermined, .denied:
            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 150_000_000)
            permissionsLogger.info(
                "screen_recording_permission_requested",
                "Requesting Screen Recording access from macOS after activating BugNarrator."
            )
            let granted = CGRequestScreenCaptureAccess()
            let finalState: ScreenCapturePermissionState = granted ? .granted : currentPermissionState()
            permissionsLogger.debug(
                "screen_recording_permission_request_completed",
                granted
                    ? "macOS reported that Screen Recording access was granted."
                    : "macOS reported that Screen Recording access was not granted.",
                metadata: [
                    "granted": granted ? "true" : "false",
                    "final_state": finalState.diagnosticsValue
                ]
            )
            return finalState == .granted ? .granted : .denied
        case .unavailable:
            permissionsLogger.error(
                "screen_recording_permission_unavailable",
                "Screen Recording access is unavailable on this Mac."
            )
            return .unavailable
        }
    }
}

@MainActor
final class ScreenCapturePermissionService: ScreenCapturePermissionServicing {
    private let permissionAccess: any ScreenCapturePermissionAccessing
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    init(permissionAccess: any ScreenCapturePermissionAccessing = SystemScreenCapturePermissionAccess()) {
        self.permissionAccess = permissionAccess
    }

    func currentStatus() -> ScreenCapturePermissionStatus {
        status(from: permissionAccess.currentPermissionState())
    }

    func recoveryGuidance(
        for status: ScreenCapturePermissionStatus,
        runtimeEnvironment _: AppRuntimeEnvironment
    ) -> ScreenCaptureRecoveryGuidance {
        switch status {
        case .notDetermined:
            return ScreenCaptureRecoveryGuidance(
                headline: "Screen Recording access will be requested when you capture a screenshot.",
                message: "BugNarrator only needs Screen Recording access for screenshots. Recording can continue without screenshots."
            )
        case .granted:
            return ScreenCaptureRecoveryGuidance(
                headline: "Screen Recording access is available.",
                message: "BugNarrator can capture screenshots in this app copy."
            )
        case .denied:
            return ScreenCaptureRecoveryGuidance(
                headline: "Screen Recording access is blocked.",
                message: "Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try the screenshot again."
            )
        case .unavailable:
            return ScreenCaptureRecoveryGuidance(
                headline: "Screen capture is unavailable.",
                message: "BugNarrator could not prepare screen capture on this Mac. Recording can continue without screenshots."
            )
        case .captureSetupFailed:
            return ScreenCaptureRecoveryGuidance(
                headline: "Screenshot capture could not start.",
                message: "BugNarrator has Screen Recording access, but macOS still could not prepare a screenshot. Recording can continue without screenshots."
            )
        case .unknownError:
            return ScreenCaptureRecoveryGuidance(
                headline: "BugNarrator could not confirm screenshot access.",
                message: "Try the screenshot again. If the problem continues, relaunch the app and include a debug bundle with your bug report."
            )
        }
    }

    func preflightForScreenshotCapture(
        screenshotCaptureService: any ScreenshotCapturing,
        hasActiveRecordingSession: Bool
    ) async -> ScreenshotCapturePreflightResult {
        permissionsLogger.info(
            "screen_capture_preflight_started",
            "Running screen capture permission and capability preflight before taking a screenshot."
        )

        guard hasActiveRecordingSession else {
            let error = AppError.noActiveSession("Start a feedback session before capturing a screenshot.")
            permissionsLogger.warning("screen_capture_preflight_no_session", error.userMessage)
            return .blocked(error)
        }

        let permissionStatus = status(from: await permissionAccess.requestPermissionIfNeeded())

        switch permissionStatus {
        case .granted:
            if let validationError = await screenshotCaptureService.validateCaptureAvailability() {
                if validationError == .screenRecordingPermissionDenied {
                    permissionsLogger.warning(
                        "screen_recording_permission_denied_after_request",
                        validationError.userMessage
                    )
                    return .needsUserAction(validationError)
                }

                permissionsLogger.error(
                    "screen_capture_capability_failed",
                    validationError.userMessage
                )
                return .failure(validationError)
            }

            return .success
        case .notDetermined:
            permissionsLogger.warning(
                "screen_recording_permission_not_determined_after_request",
                "Screen Recording access remained undecided after BugNarrator requested it."
            )
            return .needsUserAction(.screenRecordingPermissionDenied)
        case .denied:
            permissionsLogger.warning(
                "screen_recording_permission_denied",
                "Screen Recording access was denied."
            )
            return .needsUserAction(.screenRecordingPermissionDenied)
        case .unavailable:
            permissionsLogger.error(
                "screen_capture_unavailable",
                "Screen capture is unavailable on this Mac."
            )
            return .blocked(.screenshotCaptureFailure("Screen capture is unavailable on this Mac. Recording can continue without screenshots."))
        case .captureSetupFailed:
            permissionsLogger.error(
                "screen_capture_setup_failed",
                "BugNarrator could not prepare screenshot capture even though permission appears granted."
            )
            return .failure(.screenshotCaptureFailure("BugNarrator could not prepare screenshot capture. Recording can continue without screenshots."))
        case .unknownError:
            permissionsLogger.error(
                "screen_capture_permission_unknown_error",
                "BugNarrator could not confirm Screen Recording availability."
            )
            return .failure(.screenshotCaptureFailure("BugNarrator could not confirm Screen Recording availability. Recording can continue without screenshots."))
        }
    }

    private func status(from permissionState: ScreenCapturePermissionState) -> ScreenCapturePermissionStatus {
        switch permissionState {
        case .granted:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .unavailable:
            return .unavailable
        }
    }
}

private extension ScreenCapturePermissionState {
    var diagnosticsValue: String {
        switch self {
        case .granted:
            return "granted"
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .unavailable:
            return "unavailable"
        }
    }
}
