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
