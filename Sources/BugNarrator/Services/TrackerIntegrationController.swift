import Combine
import Foundation

@MainActor
final class TrackerIntegrationController: ObservableObject {
    @Published private(set) var gitHubValidationState: APIKeyValidationState = .idle
    @Published private(set) var jiraValidationState: APIKeyValidationState = .idle
    @Published private(set) var gitHubRepositories: [GitHubRepositoryOption] = []
    @Published private(set) var isLoadingGitHubRepositories = false
    @Published private(set) var jiraProjects: [JiraProjectOption] = []
    @Published private(set) var jiraIssueTypes: [JiraIssueTypeOption] = []
    @Published private(set) var isLoadingJiraIssueTypes = false
    @Published private(set) var jiraProjectMetadataIsStale = false
    @Published private(set) var jiraIssueTypeMetadataIsStale = false

    var showSettingsWindow: (() -> Void)?

    private let settingsStore: SettingsStore
    private let exportService: any IssueExporting
    private let exportLogger = DiagnosticsLogger(category: .export)
    private var cancellables = Set<AnyCancellable>()

    private var gitHubValidationRequestID = 0
    private var gitHubRepositoriesRequestID = 0
    private var jiraValidationRequestID = 0
    private var jiraIssueTypesRequestID = 0
    private var jiraIssueTypesProjectKey: String?
    private var gitHubRepositoriesTask: Task<[GitHubRepositoryOption], Error>?
    private var jiraValidationTask: Task<Void, Error>?
    private var jiraIssueTypesTask: Task<[JiraIssueTypeOption], Error>?

    init(
        settingsStore: SettingsStore,
        exportService: any IssueExporting
    ) {
        self.settingsStore = settingsStore
        self.exportService = exportService
        wireSettingsObservers()
    }

    func validateGitHubConfiguration() async {
        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        guard let configuration = settingsStore.githubExportConfiguration else {
            let error = AppError.exportConfigurationMissing(
                "GitHub export requires a token, repository owner, and repository name."
            )
            gitHubValidationState = .failure(error.userMessage)
            showSettingsWindow?()
            return
        }

        gitHubValidationRequestID += 1
        let requestID = gitHubValidationRequestID
        let configurationSnapshot = configuration
        gitHubValidationState = .validating

        do {
            try await exportService.validateGitHubConfiguration(configurationSnapshot)

            guard requestID == gitHubValidationRequestID,
                  configurationSnapshot == settingsStore.githubExportConfiguration else {
                return
            }

            gitHubValidationState = .success(
                "GitHub accepted this token for \(configurationSnapshot.owner)/\(configurationSnapshot.repository)."
            )
            exportLogger.info(
                "validate_github_configuration_succeeded",
                "GitHub export configuration validation succeeded.",
                metadata: ["repository": "\(configurationSnapshot.owner)/\(configurationSnapshot.repository)"]
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestID == gitHubValidationRequestID else {
                return
            }

            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            gitHubValidationState = .failure(appError.userMessage)
            exportLogger.warning("validate_github_configuration_failed", appError.userMessage)
        }
    }

    func loadGitHubRepositories() async {
        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        guard settingsStore.hasGitHubToken else {
            let error = AppError.exportConfigurationMissing(
                "GitHub repository discovery requires a personal access token."
            )
            gitHubValidationState = .failure(error.userMessage)
            showSettingsWindow?()
            return
        }

        gitHubRepositoriesTask?.cancel()
        gitHubRepositoriesRequestID += 1
        let requestID = gitHubRepositoriesRequestID
        let tokenSnapshot = settingsStore.trimmedGitHubToken
        isLoadingGitHubRepositories = true
        gitHubValidationState = .validating

        let task = Task {
            try await exportService.fetchGitHubRepositories(token: tokenSnapshot)
        }
        gitHubRepositoriesTask = task

        defer {
            if requestID == gitHubRepositoriesRequestID {
                isLoadingGitHubRepositories = false
            }
        }

        do {
            let repositories = try await task.value
            guard requestID == gitHubRepositoriesRequestID,
                  tokenSnapshot == settingsStore.trimmedGitHubToken else {
                return
            }

            gitHubRepositories = repositories
            refreshSelectedGitHubRepository(using: repositories)

            if repositories.isEmpty {
                gitHubValidationState = .failure("GitHub did not return any repositories where this token can create issues.")
            } else {
                gitHubValidationState = .success(
                    "Loaded \(repositories.count) GitHub repositor\(repositories.count == 1 ? "y" : "ies") where this token can create issues."
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestID == gitHubRepositoriesRequestID else {
                return
            }

            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            gitHubValidationState = .failure(appError.userMessage)
            exportLogger.warning("load_github_repositories_failed", appError.userMessage)
        }
    }

    func validateJiraConfiguration() async {
        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        guard let configuration = settingsStore.jiraConnectionConfiguration else {
            let error = AppError.exportConfigurationMissing(
                "Jira project discovery requires a base URL, email, and API token."
            )
            jiraValidationState = .failure(error.userMessage)
            showSettingsWindow?()
            return
        }

        jiraValidationTask?.cancel()
        jiraIssueTypesTask?.cancel()
        jiraValidationRequestID += 1
        let requestID = jiraValidationRequestID
        let configurationSnapshot = configuration
        let selectedProjectKey = settingsStore.normalizedJiraProjectKey
        let selectedIssueTypeName = settingsStore.normalizedJiraIssueType
        jiraValidationState = .validating

        let task = Task<Void, Error> {
            let projects = try await self.exportService.fetchJiraProjects(configurationSnapshot)

            guard !Task.isCancelled else {
                throw CancellationError()
            }

            await MainActor.run {
                guard requestID == self.jiraValidationRequestID,
                      configurationSnapshot == self.settingsStore.jiraConnectionConfiguration else {
                    return
                }

                if projects.isEmpty {
                    self.jiraProjects = []
                    self.jiraIssueTypes = []
                    self.jiraIssueTypesProjectKey = nil
                    self.jiraProjectMetadataIsStale = false
                    self.jiraIssueTypeMetadataIsStale = false
                    self.jiraValidationState = .failure("Jira did not return any accessible projects for these credentials.")
                    return
                }

                self.jiraProjects = projects
                self.jiraProjectMetadataIsStale = false
                self.refreshSelectedJiraProject(using: projects)
            }

            guard !selectedProjectKey.isEmpty else {
                await MainActor.run {
                    guard requestID == self.jiraValidationRequestID else {
                        return
                    }

                    self.jiraIssueTypes = []
                    self.jiraIssueTypesProjectKey = nil
                    self.jiraIssueTypeMetadataIsStale = false
                    self.jiraValidationState = .success(
                        "Loaded \(projects.count) Jira project\(projects.count == 1 ? "" : "s"). Choose a project to load issue types."
                    )
                }
                return
            }

            guard let selectedProject = projects.first(where: {
                $0.key == selectedProjectKey || $0.projectID == self.settingsStore.normalizedJiraProjectID
            }) else {
                await MainActor.run {
                    guard requestID == self.jiraValidationRequestID else {
                        return
                    }

                    self.jiraIssueTypes = []
                    self.jiraIssueTypesProjectKey = nil
                    self.jiraValidationState = .failure(
                        "Loaded \(projects.count) Jira project\(projects.count == 1 ? "" : "s"), but the saved project \(selectedProjectKey) is no longer available. Choose a project from the list."
                    )
                }
                return
            }

            await MainActor.run {
                guard requestID == self.jiraValidationRequestID else {
                    return
                }

                self.jiraIssueTypesTask?.cancel()
                self.jiraIssueTypesRequestID += 1
            }

            let loadResult = try await self.loadJiraIssueTypes(
                for: selectedProject,
                configuration: configurationSnapshot,
                requestID: await MainActor.run { self.jiraIssueTypesRequestID }
            )

            guard loadResult.applied else {
                return
            }

            await MainActor.run {
                guard requestID == self.jiraValidationRequestID else {
                    return
                }

                self.applyJiraIssueTypeValidationState(
                    issueTypes: loadResult.issueTypes,
                    project: selectedProject,
                    issueTypeName: selectedIssueTypeName,
                    projectCount: projects.count
                )
                self.exportLogger.info(
                    "validate_jira_configuration_succeeded",
                    "Jira export configuration validation succeeded.",
                    metadata: [
                        "project_count": "\(projects.count)",
                        "project_key": selectedProject.key
                    ]
                )
            }
        }

        jiraValidationTask = task

        do {
            try await task.value
        } catch is CancellationError {
            return
        } catch {
            guard requestID == jiraValidationRequestID else {
                return
            }

            jiraProjectMetadataIsStale = !jiraProjects.isEmpty
            jiraIssueTypeMetadataIsStale = !jiraIssueTypes.isEmpty
            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            jiraValidationState = .failure(appError.userMessage)
            exportLogger.warning("validate_jira_configuration_failed", appError.userMessage)
        }
    }

    func selectJiraProject(projectID: String) {
        guard let selectedProject = jiraProjects.first(where: { $0.projectID == projectID }) else {
            settingsStore.jiraProjectID = ""
            settingsStore.jiraProjectKey = ""
            settingsStore.jiraIssueTypeID = ""
            settingsStore.jiraIssueType = ""
            jiraIssueTypes = []
            jiraIssueTypesProjectKey = nil
            jiraIssueTypeMetadataIsStale = false
            return
        }

        settingsStore.jiraProjectID = selectedProject.projectID
        settingsStore.jiraProjectKey = selectedProject.key
        settingsStore.jiraIssueTypeID = ""
        settingsStore.jiraIssueType = ""
    }

    func refreshJiraIssueTypesForSelectedProject() async {
        guard let configuration = settingsStore.jiraConnectionConfiguration else {
            return
        }

        let projectKey = settingsStore.normalizedJiraProjectKey
        guard !projectKey.isEmpty,
              let project = jiraProjects.first(where: { $0.key == projectKey || $0.projectID == settingsStore.normalizedJiraProjectID }),
              jiraIssueTypesProjectKey != project.key else {
            return
        }

        if isLoadingJiraIssueTypes {
            jiraIssueTypesTask?.cancel()
        }

        jiraIssueTypesRequestID += 1
        let requestID = jiraIssueTypesRequestID

        do {
            let loadResult = try await loadJiraIssueTypes(
                for: project,
                configuration: configuration,
                requestID: requestID
            )

            guard loadResult.applied else {
                return
            }

            applyJiraIssueTypeValidationState(
                issueTypes: loadResult.issueTypes,
                project: project,
                issueTypeName: settingsStore.normalizedJiraIssueType,
                projectCount: nil
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestID == jiraIssueTypesRequestID else {
                return
            }

            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            jiraIssueTypeMetadataIsStale = !jiraIssueTypes.isEmpty && jiraIssueTypesProjectKey == project.key
            jiraValidationState = .failure(appError.userMessage)
            exportLogger.warning("load_jira_issue_types_failed", appError.userMessage)
        }
    }

    private func wireSettingsObservers() {
        settingsStore.$githubToken
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.gitHubValidationState = .idle
                self?.gitHubRepositories = []
                self?.gitHubRepositoriesTask?.cancel()
                self?.gitHubRepositoriesRequestID += 1
                self?.gitHubValidationRequestID += 1
                self?.isLoadingGitHubRepositories = false
            }
            .store(in: &cancellables)

        settingsStore.$githubRepositoryOwner
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.gitHubValidationState = .idle
                self?.gitHubValidationRequestID += 1
            }
            .store(in: &cancellables)

        settingsStore.$githubRepositoryName
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.gitHubValidationState = .idle
                self?.gitHubValidationRequestID += 1
            }
            .store(in: &cancellables)

        settingsStore.$jiraBaseURL
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.jiraValidationState = .idle
                self?.cancelAndResetJiraMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraEmail
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.jiraValidationState = .idle
                self?.cancelAndResetJiraMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraAPIToken
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.jiraValidationState = .idle
                self?.cancelAndResetJiraMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraProjectKey
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.jiraValidationState = .idle
                self?.jiraIssueTypesTask?.cancel()
                self?.jiraIssueTypesRequestID += 1
                self?.isLoadingJiraIssueTypes = false
                if let self, self.settingsStore.normalizedJiraProjectKey != self.jiraIssueTypesProjectKey {
                    self.jiraIssueTypes = []
                    self.jiraIssueTypesProjectKey = nil
                    self.jiraIssueTypeMetadataIsStale = false
                }
            }
            .store(in: &cancellables)

        settingsStore.$jiraIssueType
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.jiraValidationState = .idle
            }
            .store(in: &cancellables)
    }

    private func cancelAndResetJiraMetadata() {
        jiraValidationTask?.cancel()
        jiraIssueTypesTask?.cancel()
        jiraValidationRequestID += 1
        jiraIssueTypesRequestID += 1
        isLoadingJiraIssueTypes = false
        resetJiraProjectMetadata()
    }

    private func resetJiraProjectMetadata() {
        jiraProjects = []
        jiraIssueTypes = []
        jiraIssueTypesProjectKey = nil
        jiraProjectMetadataIsStale = false
        jiraIssueTypeMetadataIsStale = false
    }

    private func refreshSelectedGitHubRepository(using repositories: [GitHubRepositoryOption]) {
        if let selectedRepository = repositories.first(where: {
            $0.repositoryID == settingsStore.normalizedGitHubRepositoryID
                || ($0.owner.compare(settingsStore.normalizedGitHubRepositoryOwner, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    && $0.name.compare(settingsStore.normalizedGitHubRepositoryName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame)
        }) {
            settingsStore.githubRepositoryID = selectedRepository.repositoryID
            settingsStore.githubRepositoryOwner = selectedRepository.owner
            settingsStore.githubRepositoryName = selectedRepository.name
        }
    }

    private func refreshSelectedJiraProject(using projects: [JiraProjectOption]) {
        if let selectedProject = projects.first(where: {
            $0.projectID == settingsStore.normalizedJiraProjectID || $0.key == settingsStore.normalizedJiraProjectKey
        }) {
            settingsStore.jiraProjectID = selectedProject.projectID
            settingsStore.jiraProjectKey = selectedProject.key
        }
    }

    private func refreshSelectedJiraIssueType(using issueTypes: [JiraIssueTypeOption]) {
        if let selectedIssueType = issueTypes.first(where: {
            $0.id == settingsStore.normalizedJiraIssueTypeID
                || $0.name.compare(settingsStore.normalizedJiraIssueType, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            settingsStore.jiraIssueTypeID = selectedIssueType.id
            settingsStore.jiraIssueType = selectedIssueType.name
        }
    }

    private func loadJiraIssueTypes(
        for project: JiraProjectOption,
        configuration: JiraConnectionConfiguration,
        requestID: Int
    ) async throws -> JiraIssueTypeLoadResult {
        isLoadingJiraIssueTypes = true

        let task = Task {
            try await exportService.fetchJiraIssueTypes(
                for: project.key,
                projectID: project.projectID,
                configuration: configuration
            )
        }
        jiraIssueTypesTask = task

        defer {
            if requestID == jiraIssueTypesRequestID {
                isLoadingJiraIssueTypes = false
            }
        }

        let issueTypes = try await task.value

        guard requestID == jiraIssueTypesRequestID,
              settingsStore.normalizedJiraProjectKey == project.key else {
            return JiraIssueTypeLoadResult(issueTypes: issueTypes, applied: false)
        }

        jiraIssueTypes = issueTypes
        jiraIssueTypesProjectKey = project.key
        jiraIssueTypeMetadataIsStale = false
        refreshSelectedJiraIssueType(using: issueTypes)

        return JiraIssueTypeLoadResult(issueTypes: issueTypes, applied: true)
    }

    private func applyJiraIssueTypeValidationState(
        issueTypes: [JiraIssueTypeOption],
        project: JiraProjectOption,
        issueTypeName: String,
        projectCount: Int?
    ) {
        let projectPrefix: String
        if let projectCount {
            projectPrefix = "Loaded \(projectCount) Jira project\(projectCount == 1 ? "" : "s"). "
        } else {
            projectPrefix = ""
        }

        if issueTypeName.isEmpty {
            jiraValidationState = .success(
                "\(projectPrefix)\(project.displayLabel) has \(issueTypes.count) available issue type\(issueTypes.count == 1 ? "" : "s"). Choose one to continue."
            )
        } else if issueTypes.contains(where: {
            $0.id == settingsStore.normalizedJiraIssueTypeID
                || $0.name.compare(issueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            jiraValidationState = .success(
                "\(projectPrefix)\(project.displayLabel) is ready to export as \(settingsStore.normalizedJiraIssueType)."
            )
        } else {
            jiraValidationState = .failure(
                "Project \(project.displayLabel) does not allow issue type \(issueTypeName). Choose one of the available issue types."
            )
        }
    }
}

private struct JiraIssueTypeLoadResult {
    let issueTypes: [JiraIssueTypeOption]
    let applied: Bool
}
