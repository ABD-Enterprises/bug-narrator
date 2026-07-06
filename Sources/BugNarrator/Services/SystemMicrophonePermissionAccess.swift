import AppKit
import AVFAudio
import AVFoundation
import Foundation

@MainActor
final class SystemMicrophonePermissionAccess: MicrophonePermissionAccessing {
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    func currentPermissionState() -> MicrophonePermissionState {
        resolvedPermissionState(logMismatch: true)
    }

    func requestPermissionIfNeeded() async -> MicrophonePermissionState {
        let initialState = currentPermissionState()
        permissionsLogger.debug(
            "microphone_permission_state_read",
            "Read the current app-level microphone permission state.",
            metadata: ["state": initialState.diagnosticsValue]
        )

        switch initialState {
        case .authorized:
            permissionsLogger.debug("microphone_permission_authorized", "Microphone access is already authorized.")
            return .authorized
        case .notDetermined:
            return await requestPermissionFromSystem()
        case .denied, .restricted:
            permissionsLogger.warning(
                "microphone_permission_refreshing_blocked_state",
                "Microphone access looked blocked, so BugNarrator will reactivate and refresh the app-level permission state before finalizing the result.",
                metadata: ["state": initialState.diagnosticsValue]
            )

            NSApp.activate(ignoringOtherApps: true)
            try? await Task.sleep(nanoseconds: 150_000_000)

            let refreshedState = currentPermissionState()
            permissionsLogger.debug(
                "microphone_permission_state_refreshed",
                "Re-read the app-level microphone permission state after activating BugNarrator.",
                metadata: ["state": refreshedState.diagnosticsValue]
            )

            switch refreshedState {
            case .authorized:
                return .authorized
            case .notDetermined:
                return await requestPermissionFromSystem()
            case .denied, .restricted:
                let postRequestState = await requestPermissionFromSystem()
                if postRequestState == .authorized {
                    return .authorized
                }

                permissionsLogger.warning(
                    "microphone_permission_blocked",
                    "Microphone access is still blocked after BugNarrator refreshed and retried the app-level permission request.",
                    metadata: ["state": postRequestState.diagnosticsValue]
                )
                return postRequestState
            }
        }
    }

    private func requestPermissionFromSystem() async -> MicrophonePermissionState {
        permissionsLogger.info("microphone_permission_requested", "Requesting microphone access from macOS.")
        NSApp.activate(ignoringOtherApps: true)

        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }

        let finalState = resolvedPermissionState(logMismatch: true)
        permissionsLogger.debug(
            "microphone_permission_request_completed",
            granted
                ? "macOS reported that microphone access was granted."
                : "macOS reported that microphone access was not granted.",
            metadata: [
                "granted": granted ? "true" : "false",
                "final_state": finalState.diagnosticsValue
            ]
        )

        if granted || finalState == .authorized {
            return .authorized
        }

        return finalState
    }

    private func resolvedPermissionState(logMismatch: Bool) -> MicrophonePermissionState {
        let audioPermission = audioApplicationPermissionState()
        let capturePermission = captureDevicePermissionState()
        let resolvedPermission = MicrophonePermissionResolver.resolve(
            capturePermission: capturePermission,
            audioPermission: audioPermission
        )

        if logMismatch, audioPermission != capturePermission {
            permissionsLogger.warning(
                "microphone_permission_mismatch",
                "Microphone permission sources disagreed. BugNarrator will use the combined state that still allows a system prompt when one source remains undecided.",
                metadata: [
                    "audio_permission": audioPermission.diagnosticsValue,
                    "capture_permission": capturePermission.diagnosticsValue,
                    "resolved_permission": resolvedPermission.diagnosticsValue
                ]
            )
        }

        return resolvedPermission
    }

    private func audioApplicationPermissionState() -> MicrophonePermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return .authorized
        case .undetermined:
            return .notDetermined
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }

    private func captureDevicePermissionState() -> MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}

