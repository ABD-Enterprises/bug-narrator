import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("BugNarrator Settings")
                    .font(.title2.weight(.semibold))

                GroupBox("Before You Start") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BugNarrator requires your own OpenAI API key.")
                            .font(.headline)

                        Text("This app does not ship with OpenAI access or bundled credits. Paste your own key below before you try to transcribe a session.")
                            .foregroundStyle(.secondary)

                        Text("Transcription and issue extraction use the OpenAI API and may incur charges on your OpenAI account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("OpenAI") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(title: "OpenAI API Key") {
                            SecureField("sk-...", text: $settingsStore.apiKey)
                                .textFieldStyle(.roundedBorder)
                                .disabled(secureControlsDisabled)
                        }

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedAPIKey)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasAPIKey ? .primary : .secondary)

                            Spacer()

                            Button(appState.apiKeyValidationState == .validating ? "Validating..." : "Validate Key") {
                                Task {
                                    await appState.validateAPIKey()
                                }
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasAPIKey || appState.apiKeyValidationState == .validating)

                            Button("Remove Key", role: .destructive) {
                                appState.removeAPIKey()
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasAPIKey)
                        }

                        if let message = appState.apiKeyValidationState.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(appState.apiKeyValidationState.isFailure ? .red : .green)
                        }

                        Text(settingsStore.apiKeyStorageDescription)
                            .font(.footnote)
                            .foregroundStyle(settingsStore.apiKeyPersistenceState == .sessionOnly ? .orange : .secondary)

                        Text("BugNarrator stores the key in your macOS Keychain when available and never bundles it with the app or source code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Transcription") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(title: "Model") {
                            TextField("whisper-1", text: $settingsStore.preferredModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "Language Hint") {
                            TextField("Optional, for example en", text: $settingsStore.languageHint)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Prompt")
                                .frame(maxWidth: .infinity, alignment: .leading)

                            TextEditor(text: $settingsStore.transcriptionPrompt)
                                .font(.body)
                                .frame(height: 110)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
                        }

                        Text("Transcription uses the OpenAI audio transcription API. Keep prompt guidance short and use the language hint only when it improves recognition.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Issue Extraction") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(title: "Extraction Model") {
                            TextField("gpt-4.1-mini", text: $settingsStore.issueExtractionModel)
                                .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Run issue extraction automatically after transcription", isOn: $settingsStore.autoExtractIssues)

                        Text("Issue extraction creates draft bugs, UX issues, enhancements, and follow-ups from the transcript. Review the results before exporting them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Behavior") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Auto-copy transcript to clipboard", isOn: $settingsStore.autoCopyTranscript)
                        Toggle("Auto-save transcript to local history", isOn: $settingsStore.autoSaveTranscript)
                        Toggle("Debug mode keeps successful temp audio files", isOn: $settingsStore.debugMode)

                        Text("Screenshot capture prompts for Screen Recording permission the first time you use it if macOS requires access.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BugNarrator asks for microphone access only when you start recording.")
                            .foregroundStyle(.secondary)

                        Text("BugNarrator asks for Screen Recording access only when you capture a screenshot. Recording can continue without screenshots if you skip this permission.")
                            .foregroundStyle(.secondary)

                        Text("If you deny a permission, BugNarrator shows recovery buttons in the menu bar window so you can reopen the right System Settings pane.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Global Hotkeys") {
                    VStack(alignment: .leading, spacing: 12) {
                        hotkeyRow(title: HotkeyAction.toggleRecording.title, shortcut: $settingsStore.recordingHotkeyShortcut)
                        hotkeyRow(title: HotkeyAction.insertMarker.title, shortcut: $settingsStore.markerHotkeyShortcut)
                        hotkeyRow(title: HotkeyAction.captureScreenshot.title, shortcut: $settingsStore.screenshotHotkeyShortcut)

                        Text("Hotkeys use Carbon and do not require Accessibility access. Marker and screenshot hotkeys only work while a session is recording.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("GitHub Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(title: "Personal Access Token") {
                            SecureField("github_pat_...", text: $settingsStore.githubToken)
                                .textFieldStyle(.roundedBorder)
                                .disabled(secureControlsDisabled)
                        }

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedGitHubToken)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasGitHubToken ? .primary : .secondary)

                            Spacer()

                            Button("Remove Token", role: .destructive) {
                                settingsStore.removeGitHubToken()
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasGitHubToken)
                        }

                        labeledField(title: "Repository Owner") {
                            TextField("for example acme", text: $settingsStore.githubRepositoryOwner)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "Repository Name") {
                            TextField("for example bugnarrator", text: $settingsStore.githubRepositoryName)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "Default Labels") {
                            TextField("Comma-separated labels", text: $settingsStore.githubDefaultLabels)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text(settingsStore.githubTokenStorageDescription)
                            .font(.footnote)
                            .foregroundStyle(settingsStore.githubTokenPersistenceState == .sessionOnly ? .orange : .secondary)

                        Text("GitHub export creates Issues in the configured repository using the selected extracted issues. Screenshot filenames are referenced in the issue body for manual attachment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Jira Export") {
                    VStack(alignment: .leading, spacing: 12) {
                        labeledField(title: "Jira Cloud URL") {
                            TextField("your-domain.atlassian.net", text: $settingsStore.jiraBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "Email") {
                            TextField("you@example.com", text: $settingsStore.jiraEmail)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "API Token") {
                            SecureField("Atlassian API token", text: $settingsStore.jiraAPIToken)
                                .textFieldStyle(.roundedBorder)
                                .disabled(secureControlsDisabled)
                        }

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedJiraAPIToken)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasJiraAPIToken ? .primary : .secondary)

                            Spacer()

                            Button("Remove Token", role: .destructive) {
                                settingsStore.removeJiraAPIToken()
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasJiraAPIToken)
                        }

                        labeledField(title: "Project Key") {
                            TextField("for example FM", text: $settingsStore.jiraProjectKey)
                                .textFieldStyle(.roundedBorder)
                        }

                        labeledField(title: "Issue Type") {
                            TextField("for example Task", text: $settingsStore.jiraIssueType)
                                .textFieldStyle(.roundedBorder)
                        }

                        Text(settingsStore.jiraTokenStorageDescription)
                            .font(.footnote)
                            .foregroundStyle(settingsStore.jiraTokenPersistenceState == .sessionOnly ? .orange : .secondary)

                        Text("Jira export creates issues in Jira Cloud using the selected extracted issues. Screenshot filenames are referenced in the description for manual attachment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if secureControlsDisabled {
                    Text("Secret changes are disabled while a recording, transcription, extraction, or export is in progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var secureControlsDisabled: Bool {
        appState.status.phase == .recording || appState.status.phase == .transcribing
    }

    private func hotkeyRow(title: String, shortcut: Binding<HotkeyShortcut>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            HotkeyRecorderView(shortcut: shortcut)
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .frame(width: 150, alignment: .leading)
            content()
        }
    }
}
