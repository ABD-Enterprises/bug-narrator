import SwiftUI

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
