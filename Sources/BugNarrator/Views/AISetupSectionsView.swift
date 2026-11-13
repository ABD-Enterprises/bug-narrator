import SwiftUI

struct AISetupSectionsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    @State private var revealCredential = false
    @State private var showsProviderComparison = false
    @State private var showsInstallationDetails = false
    @ObservedObject var localServer: LocalTranscriptionManager

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
                    .labelsHidden()
                    .accessibilityIdentifier("AI provider")
                    .help("OpenAI uses cloud transcription. Local (Parakeet) transcribes on this Mac with no API key or upload required.")
                }

                providerComparison

                if settingsStore.aiProvider.credentialFieldTitle.isEmpty {
                    labeledField(title: "Credential") {
                        Text("No API key required")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                if settingsStore.aiProvider == .parakeetLocal {
                    labeledField(title: "Local server address") {
                        Text(settingsStore.openAIBaseURLValue.absoluteString)
                            .textSelection(.enabled)
                    }
                } else {
                    labeledField(title: "API Base URL") {
                        TextField(settingsStore.aiProvider.baseURLPlaceholder, text: $settingsStore.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(secureControlsDisabled)
                            .accessibilityLabel("AI provider base URL")
                            .help("The endpoint BugNarrator sends transcription requests to. Leave blank for the default.")
                    }
                }

                Text(settingsStore.aiProvider.baseURLHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if settingsStore.aiProvider == .parakeetLocal {
                    localServerControls
                }

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
                    if settingsStore.aiProvider != .parakeetLocal {
                        Text(settingsStore.maskedSelectedAIProviderCredential)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(settingsStore.hasSelectedAIProviderCredential ? .primary : .secondary)
                    }

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

                    if settingsStore.aiProvider != .parakeetLocal {
                        Button("Remove Key", role: .destructive) {
                            appState.removeAPIKey()
                        }
                        .disabled(secureControlsDisabled || !settingsStore.hasSelectedAIProviderCredential)
                    }
                }

                if let message = appState.apiKeyValidationState.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(appState.apiKeyValidationState.isFailure ? .red : .green)
                }

                // The warning next to the field and this issue are the same
                // sentence for a refused endpoint, so only one of them is
                // rendered.
                if settingsStore.shouldRenderCompatibilityIssue,
                   let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
                    Text(compatibilityIssue)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if settingsStore.aiProvider != .parakeetLocal {
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
        }
        .accessibilityIdentifier("AI Provider Setup section")
        .disabled(secureControlsDisabled)

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

                if settingsStore.aiProvider == .parakeetLocal {
                    Text("The local server does not use language hints or transcription prompts.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
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
        }
        .accessibilityIdentifier("Transcription Defaults section")
        .disabled(secureControlsDisabled)

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
                    .disabled(!settingsStore.supportsIssueExtraction || secureControlsDisabled)

                Text(issueExtractionHelpText)
                    .font(.footnote)
                    .foregroundStyle(settingsStore.supportsIssueExtraction ? Color.secondary : Color.orange)
            }
        }
        .accessibilityIdentifier("Issue Extraction section")
        .disabled(secureControlsDisabled)
    }

    private var providerComparison: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(showsProviderComparison ? "Hide provider comparison" : "Compare OpenAI and Local (Parakeet)") {
                showsProviderComparison.toggle()
            }
            .buttonStyle(.borderless)
            if showsProviderComparison {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Provider")
                        Text("OpenAI").fontWeight(.semibold)
                        Text("Local (Parakeet)").fontWeight(.semibold)
                    }
                    GridRow {
                        Text("API key")
                        Text("Required")
                        Text("Not needed")
                    }
                    GridRow {
                        Text("Processing")
                        Text("Audio sent to OpenAI")
                        Text("On this Mac")
                    }
                    GridRow {
                        Text("Issue extraction")
                        Text("Supported")
                        Text("Not supported")
                    }
                    GridRow {
                        Text("Network")
                        Text("Required")
                        Text("Offline after setup")
                    }
                }
                .font(.footnote)
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var costEstimate: some View {
        if settingsStore.aiProvider == .openAI {
            Text("OpenAI charges your account for transcription and issue extraction. Costs depend on the models and usage.")
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
                        Text(choice.title)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        settingsLabeledField(title: title, content: content)
    }

    private var localServerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if localServer.supported {
                Text("Local server download: \(localServer.downloadSize). Setup needs an internet connection; model weights download on first start and require additional disk space.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                if localServer.installed {
                    HStack {
                        Button(localServer.running ? "Stop local server" : (LocalTranscriptionManager.requiresUpgrade(localServer.directory) ? "Update local server" : "Start local server")) {
                            if localServer.running { appState.stopLocalServer(localServer) } else { localServer.start() }
                        }
                        .disabled(localServer.busy || appState.localServerControlsDisabled)
                        Button("Remove local server and models", role: .destructive) { appState.removeLocalServer(localServer) }
                            .disabled(localServer.busy || localServer.running || appState.localServerControlsDisabled)
                    }
                } else {
                    Button("Download the local transcription server") { localServer.installAndStart() }
                        .disabled(localServer.busy || localServer.package == nil || appState.localServerControlsDisabled)
                    if localServer.package == nil && localServer.busy {
                        ProgressView("Checking for a server download…")
                            .controlSize(.small)
                    }
                    if localServer.package == nil {
                        Button("Check server download") { Task { await localServer.discover() } }
                            .disabled(localServer.busy || appState.localServerControlsDisabled)
                    }
                }
                if let progress = localServer.progress {
                    ProgressView(value: progress)
                    Button("Cancel installation") { appState.stopLocalServer(localServer) }
                        .disabled(appState.localServerControlsDisabled)
                }
                Button(showsInstallationDetails ? "Hide installation details" : "Show installation details") {
                    showsInstallationDetails.toggle()
                }
                .buttonStyle(.borderless)
                if showsInstallationDetails {
                    Text("Install location: \(localServer.directory.path)")
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !localServer.message.isEmpty {
                    Text(localServer.message).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("The local server requires an Apple silicon Mac. Choose OpenAI or another compatible provider on this Mac.")
                    .font(.footnote)
            }
            Button("Use OpenAI instead") { settingsStore.aiProvider = .openAI }
                .disabled(secureControlsDisabled)
        }
        .task {
            await localServer.discover()
        }
    }

    private func sectionIntro(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}
