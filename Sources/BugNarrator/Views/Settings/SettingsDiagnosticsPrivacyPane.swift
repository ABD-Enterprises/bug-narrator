import SwiftUI

/// The "Diagnostics & Support" and "Privacy" sections of Settings, extracted
/// verbatim from `SettingsView` (#355). Pure UI relocation: the same controls,
/// bindings, and `SettingsStore` keys, rendered identically. The destructive
/// "Delete All Local Data" confirmation alert stays owned by `SettingsView`
/// (which holds the presentation state); this pane only requests it via the
/// `showDeleteAllLocalDataConfirmation` binding.
struct SettingsDiagnosticsPrivacyPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool
    @Binding var showDeleteAllLocalDataConfirmation: Bool

    private var debugInfoSnapshot: DebugInfoSnapshot {
        appState.debugInfoSnapshot
    }

    var body: some View {
        Group {
            GroupBox("Diagnostics & Support") {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSectionIntro("Use these details when filing GitHub issues or sharing a debug bundle with support.")

                    settingsLabeledField(title: "App Version") {
                        Text(debugInfoSnapshot.versionDescription)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "macOS") {
                        Text(debugInfoSnapshot.macOSVersion)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "Architecture") {
                        Text(debugInfoSnapshot.architecture)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "Transcription") {
                        Text(debugInfoSnapshot.activeTranscriptionModel)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "Issue Extraction") {
                        Text(debugInfoSnapshot.issueExtractionModel)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "Log Level") {
                        Text(debugInfoSnapshot.logLevel)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    settingsLabeledField(title: "Session ID") {
                        Text(debugInfoSnapshot.sessionID?.uuidString ?? "No active or selected session")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Attach the debug bundle and, if relevant, an exported session bundle when reporting an issue. BugNarrator never includes OpenAI, GitHub, or Jira credentials in the debug bundle.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("Privacy") {
                VStack(alignment: .leading, spacing: 12) {
                    settingsSectionIntro("Export or remove local session data without exposing stored credentials.")

                    HStack(spacing: 12) {
                        // Named as the migration path, because that is the only
                        // way session bodies survive a move to another Mac (#955).
                        Button("Export Data") {
                            Task {
                                await appState.exportPrivacyData()
                            }
                        }
                        .disabled(secureControlsDisabled)

                        Text("Creates a local JSON export of BugNarrator sessions, settings metadata, and diagnostics context. API keys, GitHub tokens, Jira credentials, and Keychain-only secrets are excluded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Delete All Local Data", role: .destructive) {
                            showDeleteAllLocalDataConfirmation = true
                        }
                        .disabled(secureControlsDisabled)

                        Text("Removes locally stored sessions, temporary recording files, export history, and diagnostics files. Saved credentials in the macOS Keychain are not deleted.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    Toggle("Send screenshots to the AI provider", isOn: $settingsStore.uploadScreenshotsForExtraction)
                        .help("Off by default. When on, issue extraction uploads up to four screenshots with the transcript so the model can see what you described.")

                    Text("Issue extraction always sends the transcript and screenshot filenames. Turning this on additionally uploads the screenshot images themselves to \(settingsStore.aiProvider.displayName). Leave it off to keep the images on this Mac.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    Toggle("Record local usage analytics", isOn: $settingsStore.operationalTelemetryEnabled)
                        .help("Records named app events (recordings started, transcriptions completed, errors) to a local file. Nothing is uploaded.")

                    Text("BugNarrator records anonymous usage events to a local file (operational-telemetry.jsonl) to help diagnose issues. The data never leaves this Mac and is included in Export Data. Turn this off to stop recording new events.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
