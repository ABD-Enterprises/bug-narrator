import AVFoundation
import CoreGraphics
import SwiftUI

/// The "Recording Audio" section of Settings, extracted verbatim from
/// `SettingsView` (#523, an #355 precursor). Pure UI relocation: same controls,
/// bindings, and `SettingsStore` keys, rendered identically.
struct SettingsRecordingAudioPane: View {
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    private var availableRecordingAudioSources: [RecordingAudioSource] {
        settingsStore.systemAudioCaptureEnabled
            ? RecordingAudioSource.allCases
            : [.microphone]
    }

    var body: some View {
        GroupBox("Recording Audio") {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionIntro("Choose what audio BugNarrator records when a session starts.")

                Toggle("System audio capture modes (experimental)", isOn: $settingsStore.systemAudioCaptureEnabled)
                    .disabled(secureControlsDisabled)

                settingsLabeledField(title: "Audio Source") {
                    Picker("Audio Source", selection: $settingsStore.recordingAudioSource) {
                        ForEach(availableRecordingAudioSources) { source in
                            Text(source.title)
                                .tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(secureControlsDisabled)
                    .accessibilityLabel("Recording audio source")
                }

                if settingsStore.recordingAudioSource.usesSystemAudio {
                    Toggle(
                        "I understand system audio can include meeting audio and other people's voices",
                        isOn: $settingsStore.hasAcceptedSystemAudioRecordingConsent
                    )
                    .disabled(secureControlsDisabled)

                    Text("Get consent before recording system audio. BugNarrator stores finished sessions locally and \(settingsStore.aiProvider == .parakeetLocal ? "processes audio on this Mac" : "sends recorded audio to \(settingsStore.aiProvider.displayName)") only when transcription runs.")
                        .font(.footnote)
                        .foregroundStyle(
                            settingsStore.hasAcceptedSystemAudioRecordingConsent
                                ? Color.secondary
                                : Color.orange
                        )
                } else if settingsStore.systemAudioCaptureEnabled {
                    Text("System audio modes need two things before you can record: tick the consent notice that appears once you pick a system-audio source, and grant BugNarrator access under System Settings > Privacy & Security > Screen & System Audio Recording (macOS prompts once, the first time capture starts).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

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
