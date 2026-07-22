import Combine
import Foundation

@MainActor
final class TrackerIntegrationController: ObservableObject {
    @Published private(set) var gitHubValidationState: APIKeyValidationState = .idle
    @Published private(set) var gitHubRepositories: [GitHubRepositoryOption] = []
    @Published private(set) var isLoadingGitHubRepositories = false

    let jira: JiraIntegrationController

    var showSettingsWindow: (() -> Void)? {
        didSet {
            jira.showSettingsWindow = showSettingsWindow
        }
    }

    private let settingsStore: SettingsStore
    private let exportService: any IssueExporting
    private let exportLogger = DiagnosticsLogger(category: .export)
    private var cancellables = Set<AnyCancellable>()

    private var gitHubValidationRequestID = 0
    private var gitHubRepositoriesRequestID = 0
    private var gitHubRepositoriesTask: Task<[GitHubRepositoryOption], Error>?

    init(
        settingsStore: SettingsStore,
        exportService: any IssueExporting
    ) {
        self.settingsStore = settingsStore
        self.exportService = exportService
        self.jira = JiraIntegrationController(
            settingsStore: settingsStore,
            exportService: exportService
        )
        wireSettingsObservers()
    }

    // MARK: - Jira 1-hop forwarding (#698, closes #637 slice A)

    var jiraValidationState: APIKeyValidationState { jira.validationState }
    var jiraProjects: [JiraProjectOption] { jira.projects }
    var jiraIssueTypes: [JiraIssueTypeOption] { jira.issueTypes }
    var jiraIssueTypesByProjectID: [String: [JiraIssueTypeOption]] { jira.issueTypesByProjectID }
    var isLoadingJiraIssueTypes: Bool { jira.isLoadingIssueTypes }
    var jiraProjectMetadataIsStale: Bool { jira.projectMetadataIsStale }
    var jiraIssueTypeMetadataIsStale: Bool { jira.issueTypeMetadataIsStale }

    func validateJiraConfiguration() async {
        await jira.validateConfiguration()
    }

    func selectJiraProject(projectID: String) {
        jira.selectProject(projectID: projectID)
    }

    func jiraIssueTypes(for target: JiraIssueExportTarget) -> [JiraIssueTypeOption] {
        jira.issueTypes(for: target)
    }

    func loadJiraIssueTypes(forProjectID projectID: String) async {
        await jira.loadIssueTypes(forProjectID: projectID)
    }

    func refreshJiraIssueTypesForSelectedProject() async {
        await jira.refreshIssueTypesForSelectedProject()
    }

    // MARK: - GitHub validation + discovery

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
                .validateGitHubConfigurationSucceeded,
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
            exportLogger.warning(.validateGitHubConfigurationFailed, appError.userMessage)
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
}
