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

