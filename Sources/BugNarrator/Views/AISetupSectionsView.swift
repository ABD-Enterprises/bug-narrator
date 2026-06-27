import SwiftUI

struct AISetupSectionsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    @State private var revealCredential = false

    var body: some View {
        GroupBox("AI Provider Setup") {
            VStack(alignment: .leading, spacing: 12) {
                sectionIntro(settingsStore.aiProvider.setupDescription)

                labeledField(title: "AI Provider") {
                    Picker("AI provider", selection: $settingsStore.aiProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("AI provider")
                    .help("OpenAI uses cloud transcription. Local (Parakeet) transcribes on this Mac with no API key or upload required.")
                }

                providerComparison

                if settingsStore.aiProvider.credentialFieldTitle.isEmpty {
                    labeledField(title: "Credential") {
                        HStack {
                            Text("No API key required")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if settingsStore.aiProvider == .parakeetLocal {
                                Text("Transcription runs entirely on this Mac.")
                                    .font(.footnote)
                                    .foregroundStyle(.green)
                            }
                        }
                        .accessibilityLabel("No AI provider credential required")
                    }
                } else {
                    labeledField(title: settingsStore.aiProvider.credentialFieldTitle) {
                        HStack(spacing: 6) {
                            CredentialTokenField(
                                placeholder: aiProviderCredentialPlaceholder,
                                text: apiKeyBinding,
                                isDisabled: secureControlsDisabled,
                                accessibilityLabel: settingsStore.aiProvider.credentialFieldTitle,
                                revealWhenNotEditing: revealCredential
                            )

                            Button {
                                revealCredential.toggle()
                            } label: {
                                Image(systemName: revealCredential ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                            .disabled(secureControlsDisabled)
                            .help(revealCredential ? "Hide the credential" : "Show the credential to verify your paste")
                            .accessibilityLabel(revealCredential ? "Hide credential" : "Show credential")
                        }
                    }

                    costEstimate
                }

                labeledField(title: "API Base URL") {
                    TextField(settingsStore.aiProvider.baseURLPlaceholder, text: $settingsStore.openAIBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(secureControlsDisabled || settingsStore.aiProvider == .parakeetLocal)
                        .accessibilityLabel("AI provider base URL")
                        .help(settingsStore.aiProvider == .parakeetLocal
                            ? "Parakeet uses localhost:8422 automatically. Start the server with: local-transcription/venv/bin/python local-transcription/server.py --preload"
                            : "The endpoint BugNarrator sends transcription requests to. Leave blank for the default.")
                }

                Text(settingsStore.aiProvider.baseURLHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let warning = settingsStore.aiBaseURLPlaintextWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Insecure endpoint warning")
                } else if let host = settingsStore.effectiveAIBaseURLHost {
                    Text("Requests go to: \(host)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Requests go to \(host)")
                }

                HStack(spacing: 12) {
                    Text(settingsStore.maskedSelectedAIProviderCredential)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(settingsStore.hasSelectedAIProviderCredential ? .primary : .secondary)

                    Spacer()

                    if appState.apiKeyValidationState == .validating {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Validating")
                    }

                    Button(apiKeyActionTitle) {
                        Task {
                            await appState.validateAPIKey()
                        }
                    }
                    .disabled(
                        secureControlsDisabled ||
                        (!settingsStore.hasSelectedAIProviderCredential &&
                            settingsStore.aiProvider.requiresAPIKey &&
                            settingsStore.selectedAIProviderCredentialPersistenceState != .keychainLocked) ||
                        appState.apiKeyValidationState == .validating
                    )
                    .help(settingsStore.aiProvider == .parakeetLocal
                        ? "Checks that the local Parakeet transcription server is running and reachable."
                        : "Validates the credential and base URL against the selected provider.")

                    Button("Remove Key", role: .destructive) {
                        appState.removeAPIKey()
                    }
                    .disabled(secureControlsDisabled || !settingsStore.hasSelectedAIProviderCredential)
                }

                if let message = appState.apiKeyValidationState.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(appState.apiKeyValidationState.isFailure ? .red : .green)
                }

                if let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
                    Text(compatibilityIssue)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Text(settingsStore.selectedAIProviderCredentialStorageDescription)
                    .font(.footnote)
                    .foregroundStyle(
                        settingsStore.selectedAIProviderCredentialPersistenceState == .sessionOnly ||
                        settingsStore.selectedAIProviderCredentialPersistenceState == .keychainLocked ||
                        settingsStore.selectedAIProviderCredentialPersistenceState == .pendingSave
                            ? .orange
                            : .secondary
                    )

                Text("BugNarrator stores the provider credential in your macOS Keychain when available and never bundles it with the app or source code.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("AI Provider Setup section")

        GroupBox("Transcription Defaults") {
            VStack(alignment: .leading, spacing: 12) {
                sectionIntro("Choose the default transcription model and language hints BugNarrator sends to the selected provider.")

                labeledField(title: "Model") {
                    modelSelection(
                        choices: settingsStore.transcriptionModelChoices,
                        selection: transcriptionModelSelection,
                        customText: $settingsStore.preferredModel,
                        placeholder: settingsStore.transcriptionModelPlaceholder,
                        accessibilityLabel: "Transcription model"
                    )
                }

                labeledField(title: "Language Hint") {
                    TextField("For English narration, keep en", text: $settingsStore.languageHint)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Transcription language hint")
                        .help("Helps the model recognize the correct language. Use 'en' for English. Clear for auto-detection.")
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
                        .accessibilityLabel("Transcription prompt")
                }

                Text("Fresh installs default the language hint to en to reduce wrong-language transcript hallucinations. Clear it only when recording non-English narration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("Transcription Defaults section")

        GroupBox("Issue Extraction") {
            VStack(alignment: .leading, spacing: 12) {
                sectionIntro("Configure how BugNarrator turns finished transcripts into reviewable draft issues.")

                labeledField(title: "Extraction Model") {
                    if settingsStore.supportsIssueExtraction {
                        modelSelection(
                            choices: settingsStore.issueExtractionModelChoices,
                            selection: issueExtractionModelSelection,
                            customText: $settingsStore.issueExtractionModel,
                            placeholder: settingsStore.issueExtractionModelPlaceholder,
                            accessibilityLabel: "Issue extraction model"
                        )
                    } else {
                        Text("Not available for Local (Parakeet)")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Issue extraction model not available for Local Parakeet")
                    }
                }

                Toggle("Run issue extraction automatically after transcription", isOn: autoExtractIssuesBinding)

                Text(issueExtractionHelpText)
                    .font(.footnote)
                    .foregroundStyle(settingsStore.supportsIssueExtraction ? Color.secondary : Color.orange)
            }
        }
        .accessibilityIdentifier("Issue Extraction section")
    }

    @ViewBuilder
    private var providerComparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            comparisonRow(label: "API key", openAI: "Required", parakeet: "Not needed")
            comparisonRow(label: "Cost", openAI: "~$0.04 / 5-min session", parakeet: "Free")
            comparisonRow(label: "Privacy", openAI: "Audio sent to OpenAI", parakeet: "Stays on device")
            comparisonRow(label: "Network", openAI: "Required", parakeet: "Offline after setup")
        }
        .font(.footnote)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Provider comparison. OpenAI requires an API key and network and sends audio to OpenAI. Local Parakeet is free, offline, and keeps audio on device.")
    }

    private func comparisonRow(label: String, openAI: String, parakeet: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(openAI)
                .fontWeight(settingsStore.aiProvider == .openAI ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(parakeet)
                .fontWeight(settingsStore.aiProvider == .parakeetLocal ? .semibold : .regular)
                .foregroundStyle(settingsStore.aiProvider == .parakeetLocal ? .green : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var costEstimate: some View {
        if settingsStore.aiProvider == .openAI {
            Text("Typical cost: about $0.04 for a 5-minute session (Whisper transcription), plus issue-extraction tokens. Switch to Local (Parakeet) for free, offline transcription.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { settingsStore.apiKey },
            set: { settingsStore.apiKey = $0 }
        )
    }

    private var aiProviderCredentialPlaceholder: String {
        switch settingsStore.selectedAIProviderCredentialPersistenceState {
        case .keychain:
            return "Stored in Keychain — type to replace"
        case .keychainLocked:
            return "Stored in Keychain — unlock to use"
        case .empty, .sessionOnly, .pendingSave:
            return "sk-..."
        }
    }

    private var transcriptionModelSelection: Binding<String> {
        Binding(
            get: {
                let model = settingsStore.preferredModelValue
                let choices = settingsStore.transcriptionModelChoices
                guard !choices.isEmpty else { return model }

                return choices.contains(where: { $0.id == model })
                    ? model
                    : choices[0].id
            },
            set: { selectedModel in
                settingsStore.preferredModel = selectedModel
            }
        )
    }

    private var issueExtractionModelSelection: Binding<String> {
        Binding(
            get: {
                let model = settingsStore.issueExtractionModelValue
                let choices = settingsStore.issueExtractionModelChoices
                guard !choices.isEmpty else { return model }

                return choices.contains(where: { $0.id == model })
                    ? model
                    : choices[0].id
            },
            set: { selectedModel in
                settingsStore.issueExtractionModel = selectedModel
            }
        )
    }

    private var autoExtractIssuesBinding: Binding<Bool> {
        Binding(
            get: { settingsStore.autoExtractIssues },
            set: { shouldAutoExtract in
                guard settingsStore.supportsIssueExtraction || !shouldAutoExtract else { return }
                settingsStore.autoExtractIssues = shouldAutoExtract
            }
        )
    }

    private var issueExtractionHelpText: String {
        if settingsStore.supportsIssueExtraction {
            return "Issue extraction creates draft bugs, UX issues, enhancements, and follow-ups from the transcript. Review the results before exporting them."
        }

        return "Local Parakeet handles transcription only. Choose OpenAI or a compatible provider when you want automatic issue extraction."
    }

    private var apiKeyActionTitle: String {
        if appState.apiKeyValidationState == .validating {
            return "Validating..."
        }

        return settingsStore.selectedAIProviderCredentialPersistenceState == .keychainLocked &&
            !settingsStore.hasSelectedAIProviderCredential
            ? "Unlock Credential"
            : (
                settingsStore.selectedAIProviderCredentialPersistenceState == .pendingSave
                    ? "Save & \(settingsStore.aiProvider.validationActionTitle)"
                    : settingsStore.aiProvider.validationActionTitle
            )
    }

    @ViewBuilder
    private func modelSelection(
        choices: [AIModelChoice],
        selection: Binding<String>,
        customText: Binding<String>,
        placeholder: String,
        accessibilityLabel: String
    ) -> some View {
        if choices.isEmpty {
            TextField(placeholder, text: customText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(accessibilityLabel)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Picker(accessibilityLabel, selection: selection) {
                    ForEach(choices) { choice in
                        Text("\(choice.title) (\(choice.id))")
                            .tag(choice.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel(accessibilityLabel)
                .accessibilityIdentifier(accessibilityLabel)

                if let selectedChoice = choices.first(where: { $0.id == selection.wrappedValue }) {
                    Text("\(selectedChoice.id) - \(selectedChoice.detail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .frame(width: 170, alignment: .leading)
            content()
        }
    }

    private func sectionIntro(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
