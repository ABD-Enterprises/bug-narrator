import AppKit
import AVFAudio
import AVFoundation
import Foundation

@MainActor
final class SystemMicrophonePermissionAccess: MicrophonePermissionAccessing {
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    func currentPermissionState() -> MicrophonePermissionState {
        audioApplicationPermissionState()
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
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let finalState = currentPermissionState()
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
}

@MainActor
final class MicrophonePermissionService: MicrophonePermissionServicing {
    private let permissionAccess: any MicrophonePermissionAccessing
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)

    init(permissionAccess: any MicrophonePermissionAccessing = SystemMicrophonePermissionAccess()) {
        self.permissionAccess = permissionAccess
    }

    func currentStatus() -> MicrophonePermissionStatus {
        status(from: permissionAccess.currentPermissionState())
    }

    func recoveryGuidance(
        for status: MicrophonePermissionStatus,
        runtimeEnvironment: AppRuntimeEnvironment
    ) -> MicrophoneRecoveryGuidance {
        let localTestingNote = runtimeEnvironment.isLocalTestingBuild
            ? "Local unsigned builds can need microphone approval again if you switch to a different app copy or rebuild into a new path. If System Settings already shows BugNarrator enabled, quit any other BugNarrator copies and retest the same app bundle path or the signed DMG build."
            : nil

        switch status {
        case .notDetermined:
            return MicrophoneRecoveryGuidance(
                headline: "Microphone access will be requested when you start recording.",
                message: "BugNarrator needs microphone access to record a feedback session. Start recording to trigger the macOS permission prompt.",
                localTestingNote: localTestingNote
            )
        case .granted:
            return MicrophoneRecoveryGuidance(
                headline: "Microphone access is available.",
                message: "BugNarrator can use the microphone on this app copy.",
                localTestingNote: runtimeEnvironment.isLocalTestingBuild ? localTestingNote : nil
            )
        case .denied:
            return MicrophoneRecoveryGuidance(
                headline: "Microphone access is blocked.",
                message: "Open System Settings > Privacy & Security > Microphone, enable BugNarrator, then try again.",
                localTestingNote: localTestingNote
            )
        case .restricted:
            return MicrophoneRecoveryGuidance(
                headline: "Microphone access is restricted.",
                message: "Microphone access is restricted on this Mac. Check System Settings > Privacy & Security > Microphone and any device-management or parental-control restrictions, then try again.",
                localTestingNote: localTestingNote
            )
        case .unavailable:
            return MicrophoneRecoveryGuidance(
                headline: "Audio capture is unavailable.",
                message: "BugNarrator could not prepare audio capture. Check that an input device is connected and available, then try again.",
                localTestingNote: localTestingNote
            )
        case .captureSetupFailed:
            return MicrophoneRecoveryGuidance(
                headline: "Microphone capture could not start.",
                message: "BugNarrator can see microphone permission, but macOS still refused recorder setup. Quit the app, reconnect your input device if needed, and try again.",
                localTestingNote: localTestingNote
            )
        case .unknownError:
            return MicrophoneRecoveryGuidance(
                headline: "BugNarrator could not confirm microphone access.",
                message: "Relaunch the app and try again. If the problem continues, export a debug bundle and include it with your bug report.",
                localTestingNote: localTestingNote
            )
        }
    }

    func preflightForRecordingStart(audioRecorder: any AudioRecording) async -> RecordingStartPreflightResult {
        permissionsLogger.info(
            "microphone_preflight_started",
            "Running microphone permission and recorder preflight before starting a session."
        )

        let permissionStatus = status(from: await permissionAccess.requestPermissionIfNeeded())

        switch permissionStatus {
        case .granted:
            return await grantedPermissionResult(audioRecorder: audioRecorder)
        case .notDetermined:
            permissionsLogger.warning(
                "microphone_permission_not_determined_after_request",
                "Microphone access remained undecided after BugNarrator requested it."
            )
            return .needsUserAction(.microphonePermissionDenied)
        case .denied:
            permissionsLogger.warning("microphone_permission_denied", "Microphone access was denied.")
            return .needsUserAction(.microphonePermissionDenied)
        case .restricted:
            permissionsLogger.warning("microphone_permission_restricted", "Microphone access is restricted.")
            return .blocked(.microphonePermissionRestricted)
        case .unavailable:
            permissionsLogger.error("microphone_unavailable", "Microphone access is unavailable.")
            return .blocked(.microphoneUnavailable("Check that an input device is connected and available, then try again."))
        case .captureSetupFailed:
            permissionsLogger.error(
                "microphone_capture_setup_failed",
                "BugNarrator could not prepare the recorder even though microphone permission appears granted."
            )
            return .failure(.microphoneUnavailable("Check that an input device is connected and available, then try again."))
        case .unknownError:
            permissionsLogger.error("microphone_permission_unknown_error", "BugNarrator could not confirm microphone availability.")
            return .failure(.microphoneUnavailable("BugNarrator could not confirm microphone availability. Relaunch the app and try again."))
        }
    }

    private func status(from permissionState: MicrophonePermissionState) -> MicrophonePermissionStatus {
        switch permissionState {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        }
    }

    private func grantedPermissionResult(
        audioRecorder: any AudioRecording
    ) async -> RecordingStartPreflightResult {
        if let activationError = await audioRecorder.validateRecordingActivation() {
            switch activationError {
            case .microphonePermissionDenied:
                permissionsLogger.warning(
                    "microphone_permission_denied_after_grant",
                    "Microphone permission looked granted, but the recorder still reported access denied."
                )
                return .needsUserAction(.microphonePermissionDenied)
            case .microphonePermissionRestricted:
                permissionsLogger.warning(
                    "microphone_permission_restricted_after_grant",
                    "Microphone permission looked granted, but the recorder still reported restricted access."
                )
                return .blocked(.microphonePermissionRestricted)
            case .microphoneUnavailable:
                permissionsLogger.error(
                    "microphone_capture_setup_failed",
                    activationError.userMessage
                )
                return .failure(activationError)
            default:
                permissionsLogger.error(
                    "microphone_activation_probe_failed",
                    activationError.userMessage
                )
                return .failure(activationError)
            }
        }

        return .success
    }
}

private extension MicrophonePermissionState {
    var diagnosticsValue: String {
        switch self {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        }
    }
}
