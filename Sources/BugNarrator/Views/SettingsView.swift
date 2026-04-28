import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BugNarrator Settings")
                        .font(.title2.weight(.semibold))

                    Text("Set up your OpenAI key, review workflow defaults, export destinations, and local diagnostics in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                statusSummary

                GroupBox("Before You Start") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("BugNarrator requires your own OpenAI API key.")
                            .font(.headline)

                        Text("BugNarrator does not ship with OpenAI access or bundled credits. Paste your own key below before you transcribe a session or run issue extraction.")
                            .foregroundStyle(.secondary)

                        Text("Transcription and issue extraction use the OpenAI API and may incur charges on your OpenAI account.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("OpenAI Setup") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Recording can start without a key, but transcription and issue extraction require your own OpenAI API key.")

                        labeledField(title: "OpenAI API Key") {
                            CredentialTokenField(
                                placeholder: "sk-...",
                                text: $settingsStore.apiKey,
                                isDisabled: secureControlsDisabled,
                                accessibilityLabel: "OpenAI API Key"
                            )
                        }

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedAPIKey)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasAPIKey ? .primary : .secondary)

                            Spacer()

                            Button(apiKeyActionTitle) {
                                Task {
                                    await appState.validateAPIKey()
                                }
                            }
                            .disabled(
                                secureControlsDisabled ||
                                (!settingsStore.hasAPIKey && settingsStore.apiKeyPersistenceState != .keychainLocked) ||
                                appState.apiKeyValidationState == .validating
                            )

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
                            .foregroundStyle(
                                settingsStore.apiKeyPersistenceState == .sessionOnly ||
                                settingsStore.apiKeyPersistenceState == .keychainLocked ||
                                settingsStore.apiKeyPersistenceState == .pendingSave
                                    ? .orange
                                    : .secondary
                            )

                        Text("BugNarrator stores the key in your macOS Keychain when available and never bundles it with the app or source code.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Transcription Defaults") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Choose the default transcription model and optional hints BugNarrator sends to OpenAI.")

                        labeledField(title: "Model") {
                            TextField("whisper-1", text: $settingsStore.preferredModel)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Transcription model")
                        }

                        labeledField(title: "Language Hint") {
                            TextField("Optional, for example en", text: $settingsStore.languageHint)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Transcription language hint")
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

                        Text("Transcription uses the OpenAI audio transcription API. Keep prompt guidance short and use the language hint only when it improves recognition.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Issue Extraction") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Configure how BugNarrator turns finished transcripts into reviewable draft issues.")

                        labeledField(title: "Extraction Model") {
                            TextField("gpt-4.1-mini", text: $settingsStore.issueExtractionModel)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Issue extraction model")
                        }

                        Toggle("Run issue extraction automatically after transcription", isOn: $settingsStore.autoExtractIssues)

                        Text("Issue extraction creates draft bugs, UX issues, enhancements, and follow-ups from the transcript. Review the results before exporting them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Workflow Defaults") {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionIntro("Control what BugNarrator does automatically after recording, transcription, and support workflows.")

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

                        Text("Completed recordings are always saved to the local session library as soon as you stop. BugNarrator keeps the session even if the app quits before you review it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("When debug mode is on, BugNarrator records extra local diagnostics, keeps successful temp audio files, and adds more validation notes to exported debug bundles.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Permissions") {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionIntro("BugNarrator only asks for the permissions it needs for recording and screenshots.")

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
                        sectionIntro("Hotkeys are optional. BugNarrator starts with every shortcut unassigned, so choose only the ones you want to use.")

                        hotkeyRow(action: .startRecording, shortcut: $settingsStore.startRecordingHotkeyShortcut)
                        hotkeyRow(action: .stopRecording, shortcut: $settingsStore.stopRecordingHotkeyShortcut)
                        hotkeyRow(action: .captureScreenshot, shortcut: $settingsStore.screenshotHotkeyShortcut)

                        if let hotkeyConflictMessage = settingsStore.hotkeyConflictMessage {
                            Text(hotkeyConflictMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Text("Hotkeys use Carbon and do not require Accessibility access. Screenshot hotkeys only work while a session is recording. If you choose a shortcut that is already assigned to another BugNarrator action, the new assignment is rejected until you clear or change the conflicting shortcut.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("GitHub Export (Experimental)") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Configure the repository BugNarrator should use when exporting selected extracted issues to GitHub Issues. This integration is still experimental.")

                        labeledField(title: "Personal Access Token") {
                            CredentialTokenField(
                                placeholder: "Paste GitHub token",
                                text: $settingsStore.githubToken,
                                isDisabled: secureControlsDisabled,
                                accessibilityLabel: "GitHub personal access token"
                            )
                        }

                        gitHubPrerequisites

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedGitHubToken)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasGitHubToken ? .primary : .secondary)

                            Spacer()

                            Button(gitHubRepositoryActionTitle) {
                                Task {
                                    await appState.loadGitHubRepositories()
                                }
                            }
                            .disabled(secureControlsDisabled || !settingsStore.gitHubRepositoryDiscoveryIsReady || appState.isLoadingGitHubRepositories)

                            Button(gitHubValidationActionTitle) {
                                Task {
                                    await appState.validateGitHubConfiguration()
                                }
                            }
                            .disabled(secureControlsDisabled || !settingsStore.gitHubConfigurationValidationIsReady || appState.gitHubValidationState == .validating)

                            Button("Remove GitHub Token", role: .destructive) {
                                settingsStore.removeGitHubToken()
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasGitHubToken)
                        }

                        labeledField(title: "Repository") {
                            if appState.gitHubRepositories.isEmpty {
                                Text(settingsStore.gitHubRepositoryDiscoveryIsReady ? "Load repositories first" : "Paste a token, then load repositories")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                Picker("GitHub repository", selection: gitHubRepositorySelection) {
                                    Text("Choose a repository")
                                        .tag("")
                                    ForEach(appState.gitHubRepositories) { repository in
                                        Text(repository.displayLabel)
                                            .tag(repository.repositoryID)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .disabled(secureControlsDisabled || appState.isLoadingGitHubRepositories)
                                .accessibilityLabel("GitHub repository")
                            }
                        }

                        labeledField(title: "Repository Owner") {
                            TextField("for example acme", text: $settingsStore.githubRepositoryOwner)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("GitHub repository owner")
                        }

                        labeledField(title: "Repository Name") {
                            TextField("for example bugnarrator", text: $settingsStore.githubRepositoryName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("GitHub repository name")
                        }

                        labeledField(title: "Default Labels") {
                            TextField("Comma-separated labels", text: $settingsStore.githubDefaultLabels)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("GitHub default labels")
                        }

                        Text(settingsStore.githubTokenStorageDescription)
                            .font(.footnote)
                            .foregroundStyle(
                                settingsStore.githubTokenPersistenceState == .sessionOnly ||
                                settingsStore.githubTokenPersistenceState == .pendingSave
                                    ? .orange
                                    : .secondary
                            )

                        if let message = appState.gitHubValidationState.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(appState.gitHubValidationState.isFailure ? .red : .green)
                        }

                        Text("Use Export to GitHub from Session Library > Extracted Issues after you extract issues from a transcript.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("GitHub export is experimental. It creates Issues in the configured repository using the selected extracted issues. Screenshot filenames are referenced in the issue body for manual attachment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Jira Export (Experimental)") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Configure the Jira Cloud project BugNarrator should use when exporting selected extracted issues. This integration is still experimental.")

                        labeledField(title: "Jira Cloud URL") {
                            TextField("your-domain.atlassian.net", text: $settingsStore.jiraBaseURL)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Jira Cloud URL")
                        }

                        labeledField(title: "Email") {
                            TextField("you@example.com", text: $settingsStore.jiraEmail)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("Jira email")
                        }

                        labeledField(title: "API Token") {
                            CredentialTokenField(
                                placeholder: "Atlassian API token",
                                text: $settingsStore.jiraAPIToken,
                                isDisabled: secureControlsDisabled,
                                accessibilityLabel: "Jira API token"
                            )
                        }

                        jiraPrerequisites

                        HStack(spacing: 12) {
                            Text(settingsStore.maskedJiraAPIToken)
                                .font(.subheadline.monospaced())
                                .foregroundStyle(settingsStore.hasJiraAPIToken ? .primary : .secondary)

                            Spacer()

                            Button(jiraValidationActionTitle) {
                                Task {
                                    await appState.validateJiraConfiguration()
                                }
                            }
                            .disabled(secureControlsDisabled || !settingsStore.jiraProjectDiscoveryIsReady || appState.jiraValidationState == .validating)

                            Button("Remove Jira Token", role: .destructive) {
                                settingsStore.removeJiraAPIToken()
                            }
                            .disabled(secureControlsDisabled || !settingsStore.hasJiraAPIToken)
                        }

                        labeledField(title: "Project") {
                            if appState.jiraProjects.isEmpty {
                                Text(settingsStore.normalizedJiraProjectKey.isEmpty ? jiraProjectPlaceholder : settingsStore.normalizedJiraProjectKey)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Jira project key")
                            } else {
                                Picker("Jira project", selection: jiraProjectSelection) {
                                    Text("Choose a project")
                                        .tag("")
                                    ForEach(appState.jiraProjects) { project in
                                        Text(project.displayLabel)
                                            .tag(project.projectID)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .disabled(secureControlsDisabled || appState.jiraValidationState == .validating)
                                .accessibilityLabel("Jira project")
                            }
                        }

                        labeledField(title: "Issue Type") {
                            if appState.jiraIssueTypes.isEmpty {
                                Text(settingsStore.normalizedJiraIssueType.isEmpty ? "Load a project first" : settingsStore.normalizedJiraIssueType)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel("Jira issue type")
                            } else {
                                Picker("Jira issue type", selection: jiraIssueTypeSelection) {
                                    Text("Choose an issue type")
                                        .tag("")
                                    ForEach(appState.jiraIssueTypes) { issueType in
                                        Text(issueType.name)
                                            .tag(issueType.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .disabled(secureControlsDisabled || appState.isLoadingJiraIssueTypes)
                                .accessibilityLabel("Jira issue type")
                            }
                        }

                        Text(settingsStore.jiraTokenStorageDescription)
                            .font(.footnote)
                            .foregroundStyle(
                                settingsStore.jiraTokenPersistenceState == .sessionOnly ||
                                settingsStore.jiraTokenPersistenceState == .pendingSave
                                    ? .orange
                                    : .secondary
                            )

                        if let message = appState.jiraValidationState.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(appState.jiraValidationState.isFailure ? .red : .green)
                        }

                        if appState.jiraProjectMetadataIsStale || appState.jiraIssueTypeMetadataIsStale {
                            Text("Showing the last successfully loaded Jira metadata. Refresh after fixing the validation error to confirm it is still current.")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }

                        Text("Use Load Jira Projects here first. Then use Export to Jira from Session Library > Extracted Issues after you extract issues from a transcript.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Text("Jira export is experimental. It creates issues in Jira Cloud using the selected extracted issues. Screenshot filenames are referenced in the description for manual attachment.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Diagnostics & Support") {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionIntro("Use these details when filing GitHub issues or sharing a debug bundle with support.")

                        labeledField(title: "App Version") {
                            Text(debugInfoSnapshot.versionDescription)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "macOS") {
                            Text(debugInfoSnapshot.macOSVersion)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "Architecture") {
                            Text(debugInfoSnapshot.architecture)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "Transcription") {
                            Text(debugInfoSnapshot.activeTranscriptionModel)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "Issue Extraction") {
                            Text(debugInfoSnapshot.issueExtractionModel)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "Log Level") {
                            Text(debugInfoSnapshot.logLevel)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        labeledField(title: "Session ID") {
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

                if secureControlsDisabled {
                    Text("Credential changes are disabled while recording, transcription, extraction, or export is in progress.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Setup Status")
                .font(.headline)

            VStack(spacing: 8) {
                settingsStatusRow(
                    title: "OpenAI",
                    detail: "Transcription and issue extraction",
                    status: openAIReadiness,
                    accessibilityLabel: "OpenAI status: \(openAIReadiness.title)"
                )

                settingsStatusRow(
                    title: "GitHub Export",
                    detail: "Issues destination",
                    status: gitHubReadiness,
                    accessibilityLabel: "GitHub export status: \(gitHubReadiness.title)"
                )

                settingsStatusRow(
                    title: "Jira Export",
                    detail: "Cloud project destination",
                    status: jiraReadiness,
                    accessibilityLabel: "Jira export status: \(jiraReadiness.title)"
                )
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private var gitHubPrerequisites: some View {
        prerequisiteChecklist(
            title: "GitHub export prerequisites",
            rows: [
                PrerequisiteRow(
                    title: "Token",
                    detail: gitHubTokenPrerequisiteDetail,
                    status: prerequisiteStatus(
                        for: settingsStore.githubTokenPersistenceState,
                        isReady: settingsStore.gitHubRepositoryDiscoveryIsReady
                    )
                ),
                PrerequisiteRow(
                    title: "Repository",
                    detail: settingsStore.gitHubConfigurationValidationIsReady
                        ? "\(settingsStore.normalizedGitHubRepositoryOwner)/\(settingsStore.normalizedGitHubRepositoryName)"
                        : "Choose or enter owner and repository name",
                    status: settingsStore.gitHubConfigurationValidationIsReady ? .ready : .needsSetup
                )
            ]
        )
    }

    private var jiraPrerequisites: some View {
        prerequisiteChecklist(
            title: "Jira export prerequisites",
            rows: [
                PrerequisiteRow(
                    title: "Credentials",
                    detail: jiraCredentialPrerequisiteDetail,
                    status: jiraCredentialPrerequisiteStatus
                ),
                PrerequisiteRow(
                    title: "Project",
                    detail: settingsStore.normalizedJiraProjectKey.isEmpty
                        ? "Load and choose a Jira project"
                        : settingsStore.normalizedJiraProjectKey,
                    status: settingsStore.normalizedJiraProjectKey.isEmpty ? .needsSetup : .ready
                ),
                PrerequisiteRow(
                    title: "Issue Type",
                    detail: settingsStore.normalizedJiraIssueType.isEmpty
                        ? "Load and choose an issue type"
                        : settingsStore.normalizedJiraIssueType,
                    status: settingsStore.normalizedJiraIssueType.isEmpty ? .needsSetup : .ready
                )
            ]
        )
    }

    private var secureControlsDisabled: Bool {
        appState.status.phase == .recording || appState.status.phase == .transcribing
    }

    private var openAIReadiness: SettingsReadinessStatus {
        credentialStatus(
            valueIsPresent: settingsStore.hasAPIKey,
            persistenceState: settingsStore.apiKeyPersistenceState
        )
    }

    private var gitHubReadiness: SettingsReadinessStatus {
        if settingsStore.githubTokenPersistenceState == .pendingSave {
            return .pendingSave
        }

        if settingsStore.githubTokenPersistenceState == .keychainLocked {
            return .locked
        }

        return settingsStore.githubExportConfiguration == nil ? .needsSetup : .ready
    }

    private var jiraReadiness: SettingsReadinessStatus {
        if settingsStore.jiraEmailPersistenceState == .pendingSave ||
            settingsStore.jiraTokenPersistenceState == .pendingSave {
            return .pendingSave
        }

        if settingsStore.jiraEmailPersistenceState == .keychainLocked ||
            settingsStore.jiraTokenPersistenceState == .keychainLocked {
            return .locked
        }

        return settingsStore.jiraExportConfiguration == nil ? .needsSetup : .ready
    }

    private var gitHubTokenPrerequisiteDetail: String {
        switch settingsStore.githubTokenPersistenceState {
        case .pendingSave:
            return "Save before loading repositories"
        case .keychainLocked:
            return "Unlock saved token"
        default:
            return settingsStore.hasGitHubToken ? "Token available" : "Paste a personal access token"
        }
    }

    private var jiraCredentialPrerequisiteDetail: String {
        if settingsStore.jiraEmailPersistenceState == .pendingSave ||
            settingsStore.jiraTokenPersistenceState == .pendingSave {
            return "Save credentials before loading projects"
        }

        if settingsStore.jiraEmailPersistenceState == .keychainLocked ||
            settingsStore.jiraTokenPersistenceState == .keychainLocked {
            return "Unlock saved Jira credentials"
        }

        if settingsStore.jiraProjectDiscoveryIsReady {
            return "URL, email, and token available"
        }

        return "Enter Jira URL, email, and API token"
    }

    private var jiraCredentialPrerequisiteStatus: SettingsReadinessStatus {
        if settingsStore.jiraEmailPersistenceState == .pendingSave ||
            settingsStore.jiraTokenPersistenceState == .pendingSave {
            return .pendingSave
        }

        if settingsStore.jiraEmailPersistenceState == .keychainLocked ||
            settingsStore.jiraTokenPersistenceState == .keychainLocked {
            return .locked
        }

        return settingsStore.jiraProjectDiscoveryIsReady ? .ready : .needsSetup
    }

    private var apiKeyActionTitle: String {
        if appState.apiKeyValidationState == .validating {
            return "Validating..."
        }

        return settingsStore.apiKeyPersistenceState == .keychainLocked && !settingsStore.hasAPIKey
            ? "Unlock Key"
            : (settingsStore.apiKeyPersistenceState == .pendingSave ? "Save & Validate Key" : "Validate Key")
    }

    private var gitHubValidationActionTitle: String {
        if appState.gitHubValidationState == .validating {
            return "Validating..."
        }

        return settingsStore.githubTokenPersistenceState == .pendingSave
            ? "Save & Validate GitHub"
            : "Validate GitHub Setup"
    }

    private var gitHubRepositoryActionTitle: String {
        if appState.isLoadingGitHubRepositories {
            return "Loading..."
        }

        return settingsStore.githubTokenPersistenceState == .pendingSave
            ? "Save & Load GitHub Repos"
            : (appState.gitHubRepositories.isEmpty ? "Load GitHub Repos" : "Refresh GitHub Repos")
    }

    private var jiraValidationActionTitle: String {
        if appState.jiraValidationState == .validating {
            return "Loading..."
        }

        return settingsStore.jiraTokenPersistenceState == .pendingSave ||
            settingsStore.jiraEmailPersistenceState == .pendingSave
            ? "Save & Load Jira Projects"
            : (appState.jiraProjects.isEmpty ? "Load Jira Projects" : "Refresh Jira Projects")
    }

    private var jiraProjectPlaceholder: String {
        settingsStore.jiraProjectDiscoveryIsReady ? "Load projects first" : "Enter Jira URL, email, and token first"
    }

    private var jiraProjectSelection: Binding<String> {
        Binding(
            get: {
                let currentProjectID = settingsStore.normalizedJiraProjectID
                let currentProjectKey = settingsStore.normalizedJiraProjectKey
                guard let selectedProject = appState.jiraProjects.first(where: {
                    $0.projectID == currentProjectID || $0.key == currentProjectKey
                }) else {
                    return appState.jiraProjects.first(where: {
                        $0.projectID == currentProjectID || $0.key == currentProjectKey
                    })?.projectID ?? ""
                }

                return selectedProject.projectID
            },
            set: { selectedProjectID in
                appState.selectJiraProject(projectID: selectedProjectID)
                Task {
                    await appState.refreshJiraIssueTypesForSelectedProject()
                }
            }
        )
    }

    private var jiraIssueTypeSelection: Binding<String> {
        Binding(
            get: {
                let currentIssueTypeID = settingsStore.normalizedJiraIssueTypeID
                let currentIssueTypeName = settingsStore.normalizedJiraIssueType
                guard let selectedIssueType = appState.jiraIssueTypes.first(where: {
                    $0.id == currentIssueTypeID
                        || $0.name.compare(currentIssueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) else {
                    return ""
                }

                return selectedIssueType.id
            },
            set: { selectedIssueTypeID in
                guard let selectedIssueType = appState.jiraIssueTypes.first(where: { $0.id == selectedIssueTypeID }) else {
                    settingsStore.jiraIssueTypeID = ""
                    settingsStore.jiraIssueType = ""
                    return
                }

                settingsStore.jiraIssueTypeID = selectedIssueType.id
                settingsStore.jiraIssueType = selectedIssueType.name
            }
        )
    }

    private var debugInfoSnapshot: DebugInfoSnapshot {
        appState.debugInfoSnapshot
    }

    private var gitHubRepositorySelection: Binding<String> {
        Binding(
            get: {
                let currentRepositoryID = settingsStore.normalizedGitHubRepositoryID
                let currentOwner = settingsStore.normalizedGitHubRepositoryOwner
                let currentRepository = settingsStore.normalizedGitHubRepositoryName
                guard let selectedRepository = appState.gitHubRepositories.first(where: {
                    $0.repositoryID == currentRepositoryID
                        || ($0.owner.compare(currentOwner, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
                            $0.name.compare(currentRepository, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame)
                }) else {
                    return ""
                }

                return selectedRepository.repositoryID
            },
            set: { selectedRepositoryID in
                guard let selectedRepository = appState.gitHubRepositories.first(where: { $0.repositoryID == selectedRepositoryID }) else {
                    settingsStore.githubRepositoryID = ""
                    return
                }

                settingsStore.githubRepositoryID = selectedRepository.repositoryID
                settingsStore.githubRepositoryOwner = selectedRepository.owner
                settingsStore.githubRepositoryName = selectedRepository.name
            }
        )
    }

    private func hotkeyRow(action: HotkeyAction, shortcut: Binding<HotkeyShortcut>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(action.title)
                .font(.subheadline.weight(.medium))
            HotkeyRecorderView(actionTitle: action.title, shortcut: shortcut)
        }
        .accessibilityElement(children: .contain)
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

    private func credentialStatus(valueIsPresent: Bool, persistenceState: APIKeyPersistenceState) -> SettingsReadinessStatus {
        switch persistenceState {
        case .pendingSave:
            return .pendingSave
        case .keychainLocked:
            return .locked
        case .empty:
            return .needsSetup
        case .keychain, .sessionOnly:
            return valueIsPresent ? .ready : .needsSetup
        }
    }

    private func prerequisiteStatus(
        for persistenceState: APIKeyPersistenceState,
        isReady: Bool
    ) -> SettingsReadinessStatus {
        switch persistenceState {
        case .pendingSave:
            return .pendingSave
        case .keychainLocked:
            return .locked
        default:
            return isReady ? .ready : .needsSetup
        }
    }

    private func settingsStatusRow(
        title: String,
        detail: String,
        status: SettingsReadinessStatus,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func prerequisiteChecklist(title: String, rows: [PrerequisiteRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(rows) { row in
                    prerequisiteRow(row)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }

    private func prerequisiteRow(_ row: PrerequisiteRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.status.symbolName)
                .foregroundStyle(row.status.color)
                .frame(width: 16)

            Text(row.title)
                .font(.caption.weight(.medium))

            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(row.status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(row.status.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.title) prerequisite: \(row.status.title)")
    }
}

private struct PrerequisiteRow: Identifiable {
    let title: String
    let detail: String
    let status: SettingsReadinessStatus

    var id: String {
        title
    }
}

private enum SettingsReadinessStatus {
    case ready
    case needsSetup
    case pendingSave
    case locked

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Needs setup"
        case .pendingSave:
            return "Pending save"
        case .locked:
            return "Locked"
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"
        case .needsSetup:
            return "exclamationmark.circle.fill"
        case .pendingSave:
            return "clock.fill"
        case .locked:
            return "lock.fill"
        }
    }

    var color: Color {
        switch self {
        case .ready:
            return .green
        case .needsSetup:
            return .orange
        case .pendingSave:
            return .blue
        case .locked:
            return .red
        }
    }
}

struct CredentialTokenField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isDisabled: Bool
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CredentialTokenTextField {
        let textField = CredentialTokenTextField()
        textField.configureCredentialInput()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        return textField
    }

    func updateNSView(_ textField: CredentialTokenTextField, context: Context) {
        context.coordinator.parent = self
        textField.configureCredentialInput()
        textField.placeholderString = placeholder
        textField.setAccessibilityLabel(accessibilityLabel)
        textField.isEnabled = !isDisabled

        let displayValue = context.coordinator.isEditing
            ? text
            : Self.maskedDisplayValue(for: text)
        if textField.stringValue != displayValue {
            textField.stringValue = displayValue
        }
    }

    static func maskedDisplayValue(for value: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return ""
        }

        let suffix = trimmedValue.suffix(min(4, trimmedValue.count))
        return "••••••••\(suffix)"
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CredentialTokenField
        var isEditing = false

        init(_ parent: CredentialTokenField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            guard let textField = notification.object as? NSTextField else {
                return
            }

            if let editor = textField.currentEditor() {
                editor.string = parent.text
                editor.selectedRange = NSRange(location: parent.text.count, length: 0)
            } else {
                textField.stringValue = parent.text
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let textField = notification.object as? NSTextField else {
                return
            }

            parent.text = textField.stringValue
            textField.stringValue = CredentialTokenField.maskedDisplayValue(for: parent.text)
        }
    }
}

final class CredentialTokenTextField: NSTextField {
    func configureCredentialInput() {
        isBezeled = true
        bezelStyle = .roundedBezel
        drawsBackground = true
        isEditable = true
        isSelectable = true
        usesSingleLineMode = true
        lineBreakMode = .byTruncatingMiddle
        isAutomaticTextCompletionEnabled = false

        if #available(macOS 11.0, *) {
            contentType = nil
        }

        cell?.isScrollable = true
        cell?.lineBreakMode = .byTruncatingMiddle
    }

    override func becomeFirstResponder() -> Bool {
        configureCredentialInput()
        let didBecomeFirstResponder = super.becomeFirstResponder()
        disableEditorAssistance()
        return didBecomeFirstResponder
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        disableEditorAssistance()
    }

    private func disableEditorAssistance() {
        guard let textView = currentEditor() as? NSTextView else {
            return
        }

        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
    }
}
