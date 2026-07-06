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
                    Text("System audio modes require a separate macOS permission prompt the first time capture starts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
