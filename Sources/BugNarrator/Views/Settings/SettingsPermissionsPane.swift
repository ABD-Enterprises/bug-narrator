import AVFoundation
import SwiftUI

/// The "Permissions" section of Settings, extracted verbatim from `SettingsView`
/// (#523). Surfaces microphone / screen-recording recovery rows when access is
/// blocked. Pure UI relocation.
struct SettingsPermissionsPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore

    private var microphonePermissionBlocked: Bool {
        guard settingsStore.recordingAudioSource.usesMicrophone else {
            return false
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            return true
        case .authorized, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private var screenRecordingPermissionMissing: Bool {
        !CGPreflightScreenCaptureAccess()
    }

    var body: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro("BugNarrator only asks for the permissions it needs for recording and screenshots.")

                Text("BugNarrator asks for microphone access only when you start recording.")
                    .foregroundStyle(.secondary)

                Text("BugNarrator asks for Screen & System Audio Recording access only when a system audio mode starts.")
                    .foregroundStyle(.secondary)

                Text("BugNarrator asks for Screen Recording access only when you capture a screenshot. Recording can continue without screenshots if you skip this permission.")
                    .foregroundStyle(.secondary)

                Text("If you deny a permission, BugNarrator shows recovery buttons in the menu bar window so you can reopen the right System Settings pane.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if microphonePermissionBlocked {
                    permissionRecoveryRow(
                        title: "Microphone access is blocked.",
                        message: "Open System Settings, enable BugNarrator for Microphone access, then start recording again.",
                        buttonTitle: "Open Microphone Settings",
                        action: appState.openMicrophonePrivacySettings
                    )
                }

                if screenRecordingPermissionMissing {
                    permissionRecoveryRow(
                        title: "Screenshot access is not enabled.",
                        message: "Recording can continue without screenshots. Enable Screen Recording if you want screenshots during a session.",
                        buttonTitle: "Open Screen Recording Settings",
                        action: appState.openScreenRecordingPrivacySettings
                    )
                }
            }
        }
    }

    private func permissionRecoveryRow(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(buttonTitle, action: action)
                .controlSize(.small)
        }
        .padding(.top, 4)
    }
}
