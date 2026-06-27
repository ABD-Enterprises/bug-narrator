import SwiftUI

/// The "GitHub Export" section of Settings, extracted verbatim from
/// `SettingsView` (#530, #355 A3b). Pure UI relocation: same controls,
/// bindings, and `SettingsStore` keys, rendered identically. Uses the shared
/// readiness layer (`SettingsReadiness`, `settingsPrerequisiteChecklist`).
struct SettingsGitHubExportPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    var body: some View {
        GroupBox("GitHub Export (Experimental)") {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionIntro("Configure the repository BugNarrator should use when exporting selected extracted issues to GitHub Issues. This integration is still experimental.")

                settingsLabeledField(title: "Personal Access Token") {
                    CredentialTokenField(
                        placeholder: "Paste GitHub token",
                        text: $settingsStore.githubToken,
                        isDisabled: secureControlsDisabled,
                        accessibilityLabel: "GitHub personal access token"
                    )
                    .help(secureControlsDisabled ? settingsSecureControlsDisabledHint : "Paste a GitHub personal access token with the repo scope.")
                }

                Link("Generate a GitHub token →", destination: BugNarratorLinks.generateGitHubToken)
                    .font(.footnote)

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

                settingsLabeledField(title: "Repository") {
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

                settingsLabeledField(title: "Repository Owner") {
                    TextField("for example acme", text: $settingsStore.githubRepositoryOwner)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("GitHub repository owner")
                }

                settingsLabeledField(title: "Repository Name") {
                    TextField("for example bugnarrator", text: $settingsStore.githubRepositoryName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("GitHub repository name")
                }

                settingsLabeledField(title: "Default Labels") {
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
    }

    private var gitHubPrerequisites: some View {
        settingsPrerequisiteChecklist(
            title: "GitHub export prerequisites",
            rows: [
                PrerequisiteRow(
                    title: "Token",
                    detail: gitHubTokenPrerequisiteDetail,
                    status: SettingsReadiness.prerequisiteStatus(
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
}

/// The "Jira Export" section of Settings, extracted verbatim from `SettingsView`
/// (#530, #355 A3b). Pure UI relocation.
struct SettingsJiraExportPane: View {
    @ObservedObject var appState: AppState
    @ObservedObject var settingsStore: SettingsStore
    let secureControlsDisabled: Bool

    var body: some View {
        GroupBox("Jira Export (Experimental)") {
            VStack(alignment: .leading, spacing: 12) {
                settingsSectionIntro("Configure the Jira Cloud project BugNarrator should use when exporting selected extracted issues. This integration is still experimental.")

                settingsLabeledField(title: "Jira Cloud URL") {
                    TextField("your-domain.atlassian.net", text: $settingsStore.jiraBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Jira Cloud URL")
                }

                if let warning = settingsStore.jiraBaseURLPlaintextWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Insecure Jira endpoint warning")
                }

                settingsLabeledField(title: "Email") {
                    TextField("you@example.com", text: $settingsStore.jiraEmail)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Jira email")
                }

                settingsLabeledField(title: "API Token") {
                    CredentialTokenField(
                        placeholder: "Atlassian API token",
                        text: $settingsStore.jiraAPIToken,
                        isDisabled: secureControlsDisabled,
                        accessibilityLabel: "Jira API token"
                    )
                    .help(secureControlsDisabled ? settingsSecureControlsDisabledHint : "Paste an Atlassian API token created for your Jira Cloud account.")
                }

                Link("Generate a Jira API token →", destination: BugNarratorLinks.generateJiraToken)
                    .font(.footnote)

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

                settingsLabeledField(title: "Project") {
                    if appState.jiraProjects.isEmpty {
                        HStack {
                            Text(settingsStore.normalizedJiraProjectKey.isEmpty ? jiraProjectPlaceholder : settingsStore.normalizedJiraProjectKey)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Jira project key")
                            if settingsStore.jiraProjectDiscoveryIsReady {
                                Button("Load Projects") {
                                    Task { await appState.validateJiraConfiguration() }
                                }
                                .controlSize(.small)
                                .disabled(secureControlsDisabled || appState.jiraValidationState == .validating)
                            }
                        }
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

                settingsLabeledField(title: "Issue Type") {
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
    }

    private var jiraPrerequisites: some View {
        settingsPrerequisiteChecklist(
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
}
