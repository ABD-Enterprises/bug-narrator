import SwiftUI

/// The "Workflow Defaults" section of Settings, extracted verbatim from
/// `SettingsView` (#355). Pure UI relocation: same toggles, bindings, and
/// `SettingsStore` keys, rendered identically.
struct SettingsWorkflowDefaultsPane: View {
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        GroupBox("Workflow Defaults") {
            VStack(alignment: .leading, spacing: 10) {
                settingsSectionIntro("Control what BugNarrator does automatically after recording, transcription, and support workflows.")

                Toggle("Auto-copy transcript to clipboard", isOn: $settingsStore.autoCopyTranscript)
                Toggle("Open BugNarrator at startup", isOn: $settingsStore.openAtStartup)
                    .disabled(!settingsStore.openAtStartupControlIsEnabled)
                Toggle("Debug mode enables verbose local diagnostics", isOn: $settingsStore.debugMode)

                if let openAtStartupStatusMessage = settingsStore.openAtStartupStatusMessage {
                    Text(openAtStartupStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(calloutColor(for: settingsStore.openAtStartupStatusTone))
                }

                Text("Screenshot capture prompts for Screen Recording permission the first time you use it if macOS requires access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("When transcription cannot finish after a recording stops, BugNarrator saves the recording locally as a pending session so you can retry transcription.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("When debug mode is on, BugNarrator records extra local diagnostics, keeps successful temp audio files, and adds more validation notes to exported debug bundles.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calloutColor(for tone: SettingsCalloutTone) -> Color {
        switch tone {
        case .secondary:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
