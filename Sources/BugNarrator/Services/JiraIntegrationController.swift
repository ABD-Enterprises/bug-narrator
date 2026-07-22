import Combine
import Foundation

/// Jira sub-controller extracted from `TrackerIntegrationController` (#698,
/// slice A of #637). Owns all Jira project/issue-type discovery + validation
/// state. `TrackerIntegrationController` retains 1-hop forwarding computed
/// properties so `appState.jiraValidationState` etc. continue to work.
@MainActor
final class JiraIntegrationController: ObservableObject {
    @Published private(set) var validationState: APIKeyValidationState = .idle
    @Published private(set) var projects: [JiraProjectOption] = []
    @Published private(set) var issueTypes: [JiraIssueTypeOption] = []
    @Published private(set) var issueTypesByProjectID: [String: [JiraIssueTypeOption]] = [:]
    @Published private(set) var isLoadingIssueTypes = false
    @Published private(set) var projectMetadataIsStale = false
    @Published private(set) var issueTypeMetadataIsStale = false

    var showSettingsWindow: (() -> Void)?

    private let settingsStore: SettingsStore
    private let exportService: any IssueExporting
    private let exportLogger = DiagnosticsLogger(category: .export)
    private var cancellables = Set<AnyCancellable>()

    private var validationRequestID = 0
    private var issueTypesRequestID = 0
    private var issueTypesProjectKey: String?
    private var validationTask: Task<Void, Error>?
    private var issueTypesTask: Task<[JiraIssueTypeOption], Error>?

    init(
        settingsStore: SettingsStore,
        exportService: any IssueExporting
    ) {
        self.settingsStore = settingsStore
        self.exportService = exportService
        wireSettingsObservers()
    }

    func validateConfiguration() async {
        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        guard let configuration = settingsStore.jiraConnectionConfiguration else {
            let error = AppError.exportConfigurationMissing(
                "Jira project discovery requires a base URL, email, and API token."
            )
            validationState = .failure(error.userMessage)
            showSettingsWindow?()
            return
        }

        validationTask?.cancel()
        issueTypesTask?.cancel()
        validationRequestID += 1
        let requestID = validationRequestID
        let configurationSnapshot = configuration
        let selectedProjectKey = settingsStore.normalizedJiraProjectKey
        let selectedIssueTypeName = settingsStore.normalizedJiraIssueType
        validationState = .validating

        let task = Task<Void, Error> {
            let projects = try await self.exportService.fetchJiraProjects(configurationSnapshot)

            guard !Task.isCancelled else {
                throw CancellationError()
            }

            await MainActor.run {
                guard requestID == self.validationRequestID,
                      configurationSnapshot == self.settingsStore.jiraConnectionConfiguration else {
                    return
                }

                if projects.isEmpty {
                    self.projects = []
                    self.issueTypes = []
                    self.issueTypesProjectKey = nil
                    self.projectMetadataIsStale = false
                    self.issueTypeMetadataIsStale = false
                    self.validationState = .failure("Jira did not return any accessible projects for these credentials.")
                    return
                }

                self.projects = projects
                self.projectMetadataIsStale = false
                self.refreshSelectedProject(using: projects)
            }

            guard !selectedProjectKey.isEmpty else {
                await MainActor.run {
                    guard requestID == self.validationRequestID else {
                        return
                    }

                    self.issueTypes = []
                    self.issueTypesProjectKey = nil
                    self.issueTypeMetadataIsStale = false
                    self.validationState = .success(
                        "Loaded \(projects.count) Jira project\(projects.count == 1 ? "" : "s"). Choose a project to load issue types."
                    )
                }
                return
            }

            guard let selectedProject = projects.first(where: {
                $0.key == selectedProjectKey || $0.projectID == self.settingsStore.normalizedJiraProjectID
            }) else {
                await MainActor.run {
                    guard requestID == self.validationRequestID else {
                        return
                    }

                    self.issueTypes = []
                    self.issueTypesProjectKey = nil
                    self.validationState = .failure(
                        "Loaded \(projects.count) Jira project\(projects.count == 1 ? "" : "s"), but the saved project \(selectedProjectKey) is no longer available. Choose a project from the list."
                    )
                }
                return
            }

            await MainActor.run {
                guard requestID == self.validationRequestID else {
                    return
                }

                self.issueTypesTask?.cancel()
                self.issueTypesRequestID += 1
            }

            let loadResult = try await self.loadIssueTypes(
                for: selectedProject,
                configuration: configurationSnapshot,
                requestID: await MainActor.run { self.issueTypesRequestID }
            )

            guard loadResult.applied else {
                return
            }

            await MainActor.run {
                guard requestID == self.validationRequestID else {
                    return
                }

                self.applyIssueTypeValidationState(
                    issueTypes: loadResult.issueTypes,
                    project: selectedProject,
                    issueTypeName: selectedIssueTypeName,
                    projectCount: projects.count
                )
                self.exportLogger.info(
                    .validateJiraConfigurationSucceeded,
                    "Jira export configuration validation succeeded.",
                    metadata: [
                        "project_count": "\(projects.count)",
                        "project_key": selectedProject.key
                    ]
                )
            }
        }

        validationTask = task

        do {
            try await task.value
        } catch is CancellationError {
            return
        } catch {
            guard requestID == validationRequestID else {
                return
            }

            projectMetadataIsStale = !projects.isEmpty
            issueTypeMetadataIsStale = !issueTypes.isEmpty
            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            validationState = .failure(appError.userMessage)
            exportLogger.warning(.validateJiraConfigurationFailed, appError.userMessage)
        }
    }

    func selectProject(projectID: String) {
        guard let selectedProject = projects.first(where: { $0.projectID == projectID }) else {
            settingsStore.jiraProjectID = ""
            settingsStore.jiraProjectKey = ""
            settingsStore.jiraIssueTypeID = ""
            settingsStore.jiraIssueType = ""
            issueTypes = []
            issueTypesProjectKey = nil
            issueTypeMetadataIsStale = false
            return
        }

        settingsStore.jiraProjectID = selectedProject.projectID
        settingsStore.jiraProjectKey = selectedProject.key
        settingsStore.jiraIssueTypeID = ""
        settingsStore.jiraIssueType = ""
    }

    func issueTypes(for target: JiraIssueExportTarget) -> [JiraIssueTypeOption] {
        let keys = [
            target.projectID,
            target.projectKey.nilIfEmpty
        ].compactMap { $0 }

        for key in keys {
            if let issueTypes = issueTypesByProjectID[key] {
                return issueTypes
            }
        }

        if target.projectKey == issueTypesProjectKey {
            return issueTypes
        }

        return []
    }

    func loadIssueTypes(forProjectID projectID: String) async {
        guard let configuration = settingsStore.jiraConnectionConfiguration,
              let project = projects.first(where: { $0.projectID == projectID }) else {
            return
        }

        if isLoadingIssueTypes {
            issueTypesTask?.cancel()
        }

        issueTypesRequestID += 1
        let requestID = issueTypesRequestID
        isLoadingIssueTypes = true

        let task = Task {
            try await exportService.fetchJiraIssueTypes(
                for: project.key,
                projectID: project.projectID,
                configuration: configuration
            )
        }
        issueTypesTask = task

        defer {
            if requestID == issueTypesRequestID {
                isLoadingIssueTypes = false
            }
        }

        do {
            let issueTypes = try await task.value
            guard requestID == issueTypesRequestID else {
                return
            }

            cacheIssueTypes(issueTypes, for: project)

            if settingsStore.normalizedJiraProjectKey == project.key {
                self.issueTypes = issueTypes
                issueTypesProjectKey = project.key
                issueTypeMetadataIsStale = false
                refreshSelectedIssueType(using: issueTypes)
            }

            validationState = .success(
                "\(project.displayLabel) has \(issueTypes.count) available issue type\(issueTypes.count == 1 ? "" : "s")."
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestID == issueTypesRequestID else {
                return
            }

            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            validationState = .failure(appError.userMessage)
            exportLogger.warning("load_jira_issue_types_failed", appError.userMessage)
        }
    }

    func refreshIssueTypesForSelectedProject() async {
        guard let configuration = settingsStore.jiraConnectionConfiguration else {
            return
        }

        let projectKey = settingsStore.normalizedJiraProjectKey
        guard !projectKey.isEmpty,
              let project = projects.first(where: { $0.key == projectKey || $0.projectID == settingsStore.normalizedJiraProjectID }),
              issueTypesProjectKey != project.key else {
            return
        }

        if isLoadingIssueTypes {
            issueTypesTask?.cancel()
        }

        issueTypesRequestID += 1
        let requestID = issueTypesRequestID

        do {
            let loadResult = try await loadIssueTypes(
                for: project,
                configuration: configuration,
                requestID: requestID
            )

            guard loadResult.applied else {
                return
            }

            applyIssueTypeValidationState(
                issueTypes: loadResult.issueTypes,
                project: project,
                issueTypeName: settingsStore.normalizedJiraIssueType,
                projectCount: nil
            )
        } catch is CancellationError {
            return
        } catch {
            guard requestID == issueTypesRequestID else {
                return
            }

            let appError = (error as? AppError) ?? .exportFailure(error.localizedDescription)
            issueTypeMetadataIsStale = !issueTypes.isEmpty && issueTypesProjectKey == project.key
            validationState = .failure(appError.userMessage)
            exportLogger.warning("load_jira_issue_types_failed", appError.userMessage)
        }
    }

    private func wireSettingsObservers() {
        settingsStore.$jiraBaseURL
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.validationState = .idle
                self?.cancelAndResetMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraEmail
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.validationState = .idle
                self?.cancelAndResetMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraAPIToken
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.validationState = .idle
                self?.cancelAndResetMetadata()
            }
            .store(in: &cancellables)

        settingsStore.$jiraProjectKey
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.validationState = .idle
                self?.issueTypesTask?.cancel()
                self?.issueTypesRequestID += 1
                self?.isLoadingIssueTypes = false
                if let self, self.settingsStore.normalizedJiraProjectKey != self.issueTypesProjectKey {
                    self.issueTypes = []
                    self.issueTypesProjectKey = nil
                    self.issueTypeMetadataIsStale = false
                }
            }
            .store(in: &cancellables)

        settingsStore.$jiraIssueType
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.validationState = .idle
            }
            .store(in: &cancellables)
    }

    private func cancelAndResetMetadata() {
        validationTask?.cancel()
        issueTypesTask?.cancel()
        validationRequestID += 1
        issueTypesRequestID += 1
        isLoadingIssueTypes = false
        resetProjectMetadata()
    }

    private func resetProjectMetadata() {
        projects = []
        issueTypes = []
        issueTypesByProjectID = [:]
        issueTypesProjectKey = nil
        projectMetadataIsStale = false
        issueTypeMetadataIsStale = false
    }

    private func refreshSelectedProject(using projects: [JiraProjectOption]) {
        if let selectedProject = projects.first(where: {
            $0.projectID == settingsStore.normalizedJiraProjectID || $0.key == settingsStore.normalizedJiraProjectKey
        }) {
            settingsStore.jiraProjectID = selectedProject.projectID
            settingsStore.jiraProjectKey = selectedProject.key
        }
    }

    private func refreshSelectedIssueType(using issueTypes: [JiraIssueTypeOption]) {
        if let selectedIssueType = issueTypes.first(where: {
            $0.id == settingsStore.normalizedJiraIssueTypeID
                || $0.name.compare(settingsStore.normalizedJiraIssueType, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            settingsStore.jiraIssueTypeID = selectedIssueType.id
            settingsStore.jiraIssueType = selectedIssueType.name
        }
    }

    private func loadIssueTypes(
        for project: JiraProjectOption,
        configuration: JiraConnectionConfiguration,
        requestID: Int
    ) async throws -> JiraIssueTypeLoadResult {
        isLoadingIssueTypes = true

        let task = Task {
            try await exportService.fetchJiraIssueTypes(
                for: project.key,
                projectID: project.projectID,
                configuration: configuration
            )
        }
        issueTypesTask = task

        defer {
            if requestID == issueTypesRequestID {
                isLoadingIssueTypes = false
            }
        }

        let issueTypes = try await task.value

        guard requestID == issueTypesRequestID,
              settingsStore.normalizedJiraProjectKey == project.key else {
            return JiraIssueTypeLoadResult(issueTypes: issueTypes, applied: false)
        }

        self.issueTypes = issueTypes
        issueTypesProjectKey = project.key
        cacheIssueTypes(issueTypes, for: project)
        issueTypeMetadataIsStale = false
        refreshSelectedIssueType(using: issueTypes)

        return JiraIssueTypeLoadResult(issueTypes: issueTypes, applied: true)
    }

    private func cacheIssueTypes(_ issueTypes: [JiraIssueTypeOption], for project: JiraProjectOption) {
        issueTypesByProjectID[project.projectID] = issueTypes
        issueTypesByProjectID[project.key] = issueTypes
    }

    private func applyIssueTypeValidationState(
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
            validationState = .success(
                "\(projectPrefix)\(project.displayLabel) has \(issueTypes.count) available issue type\(issueTypes.count == 1 ? "" : "s"). Choose one to continue."
            )
        } else if issueTypes.contains(where: {
            $0.id == settingsStore.normalizedJiraIssueTypeID
                || $0.name.compare(issueTypeName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            validationState = .success(
                "\(projectPrefix)\(project.displayLabel) is ready to export as \(settingsStore.normalizedJiraIssueType)."
            )
        } else {
            validationState = .failure(
                "Project \(project.displayLabel) does not allow issue type \(issueTypeName). Choose one of the available issue types."
            )
        }
    }
}

private struct JiraIssueTypeLoadResult {
    let issueTypes: [JiraIssueTypeOption]
    let applied: Bool
}
