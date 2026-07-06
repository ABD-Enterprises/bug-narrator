import SwiftUI

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
