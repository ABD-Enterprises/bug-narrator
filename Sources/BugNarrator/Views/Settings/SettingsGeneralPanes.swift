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

/// The "Global Hotkeys" section of Settings, extracted verbatim from
/// `SettingsView` (#355). Pure UI relocation.
struct SettingsGlobalHotkeysPane: View {
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    var body: some View {
        GroupBox("Global Hotkeys") {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionIntro("Hotkeys are optional. BugNarrator starts with every shortcut unassigned, so choose only the ones you want to use.")

                hotkeyRow(action: .startRecording, shortcut: $settingsStore.startRecordingHotkeyShortcut)
                hotkeyRow(action: .stopRecording, shortcut: $settingsStore.stopRecordingHotkeyShortcut)
                hotkeyRow(action: .captureScreenshot, shortcut: $settingsStore.screenshotHotkeyShortcut)

                if let hotkeyConflictMessage = settingsStore.hotkeyConflictMessage {
                    HStack(spacing: 8) {
                        Text(hotkeyConflictMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                        if let conflicting = settingsStore.conflictingHotkeyAction {
                            Button("Clear \(conflicting.title)") {
                                settingsStore.clearHotkey(for: conflicting)
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Text("Hotkeys use Carbon and do not require Accessibility access. Screenshot hotkeys only work while a session is recording. If you choose a shortcut that is already assigned to another BugNarrator action, the new assignment is rejected until you clear or change the conflicting shortcut.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func hotkeyRow(action: HotkeyAction, shortcut: Binding<HotkeyShortcut>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(action.title)
                .font(.subheadline.weight(.medium))
            HotkeyRecorderView(actionTitle: action.title, shortcut: shortcut)

            if !shortcut.wrappedValue.isEnabled,
               let suggestion = settingsStore.suggestedShortcutIfAvailable(for: action) {
                Button("Use suggested: \(suggestion.displayString)") {
                    shortcut.wrappedValue = suggestion
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(secureControlsDisabled)
                .help("Apply the recommended shortcut for \(action.title).")
                .accessibilityLabel("Use suggested shortcut \(suggestion.displayString) for \(action.title)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
