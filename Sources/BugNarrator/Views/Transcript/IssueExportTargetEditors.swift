import SwiftUI

/// GitHub issue-export target editor extracted from TranscriptView (#632, #401
/// slice e). Renders the row-level layout for a single ExtractedIssue's GitHub
/// target: label, status text, "Load Repos" button, owner/repository fields
/// or repository picker (when repositories have been discovered), and labels
/// field.
///
/// Binding threading is done at the callsite — TranscriptView pre-builds the
/// four bindings (owner, repository, repositorySelection, labels) using its
/// existing helpers (`issueGitHubTargetTextBinding`,
/// `issueGitHubRepositorySelection`, `issueGitHubLabelsBinding`) and passes
/// them in. That keeps `effectiveGitHubTarget` / `updateGitHubTarget` /
/// `parsedLabels` private to TranscriptView (they have other callers) and
/// lets this view stay independent of the transcript-store details.
///
/// Pixel-preserving: the body is a verbatim relocation of the pre-extraction
/// `issueGitHubTargetEditor(issue:session:)` body.
struct IssueGitHubTargetEditor: View {
    let issue: ExtractedIssue
    let target: GitHubIssueExportTarget
    @ObservedObject var appState: AppState
    let ownerBinding: Binding<String>
    let repositoryBinding: Binding<String>
    let repositorySelection: Binding<String>
    let labelsBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("GitHub", systemImage: "shippingbox")
                    .font(.caption.weight(.semibold))

                Text(target.displayLabel)
                    .font(.caption)
                    .foregroundStyle(target.isComplete ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Button(appState.isLoadingGitHubRepositories ? "Loading..." : "Load Repos") {
                    Task {
                        await appState.loadGitHubRepositories()
                    }
                }
                .disabled(!appState.settingsStore.hasGitHubToken || appState.isLoadingGitHubRepositories)
            }

            if appState.gitHubRepositories.isEmpty {
                HStack(spacing: 8) {
                    TextField(
                        "owner",
                        text: ownerBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("GitHub repository owner for \(issue.title)")

                    TextField(
                        "repository",
                        text: repositoryBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("GitHub repository name for \(issue.title)")
                }
            } else {
                Picker("GitHub Repository", selection: repositorySelection) {
                    Text("Choose repository").tag("")
                    ForEach(appState.gitHubRepositories) { repository in
                        Text(repository.displayLabel).tag(repository.repositoryID)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("GitHub repository for \(issue.title)")
            }

            TextField(
                "Labels, comma-separated",
                text: labelsBinding
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("GitHub labels for \(issue.title)")
        }
    }
}

/// Jira issue-export target editor extracted from TranscriptView (#632, #401
/// slice e). Renders the row-level layout for a single ExtractedIssue's Jira
/// target: label, status text, "Load Projects" button, project key/picker,
/// and issue-type field/picker.
///
/// Pixel-preserving: verbatim relocation of the pre-extraction
/// `issueJiraTargetEditor(issue:session:)` body.
struct IssueJiraTargetEditor: View {
    let issue: ExtractedIssue
    let target: JiraIssueExportTarget
    let issueTypes: [JiraIssueTypeOption]
    @ObservedObject var appState: AppState
    let projectKeyBinding: Binding<String>
    let projectSelection: Binding<String>
    let issueTypeNameBinding: Binding<String>
    let issueTypeSelection: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("Jira", systemImage: "list.bullet.rectangle")
                    .font(.caption.weight(.semibold))

                Text(target.isComplete ? "\(target.projectKey) / \(target.issueTypeName.isEmpty ? target.issueTypeID : target.issueTypeName)" : "Choose project and issue type")
                    .font(.caption)
                    .foregroundStyle(target.isComplete ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Button(appState.jiraValidationState == .validating ? "Loading..." : "Load Projects") {
                    Task {
                        await appState.validateJiraConfiguration()
                    }
                }
                .disabled(!appState.settingsStore.jiraProjectDiscoveryIsReady || appState.jiraValidationState == .validating)
            }

            if appState.jiraProjects.isEmpty {
                TextField(
                    "Project key",
                    text: projectKeyBinding
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Jira project key for \(issue.title)")
            } else {
                Picker("Jira Project", selection: projectSelection) {
                    Text("Choose project").tag("")
                    ForEach(appState.jiraProjects) { project in
                        Text(project.displayLabel).tag(project.projectID)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Jira project for \(issue.title)")
            }

            if issueTypes.isEmpty {
                HStack(spacing: 8) {
                    TextField(
                        "Issue type",
                        text: issueTypeNameBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Jira issue type for \(issue.title)")

                    Button(appState.isLoadingJiraIssueTypes ? "Loading..." : "Load Types") {
                        guard let projectID = target.projectID else {
                            return
                        }

                        Task {
                            await appState.loadJiraIssueTypes(forProjectID: projectID)
                        }
                    }
                    .disabled(target.projectID == nil || appState.isLoadingJiraIssueTypes)
                }
            } else {
                Picker("Jira Issue Type", selection: issueTypeSelection) {
                    Text("Choose issue type").tag("")
                    ForEach(issueTypes) { issueType in
                        Text(issueType.name).tag(issueType.id)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Jira issue type for \(issue.title)")
            }
        }
    }
}
