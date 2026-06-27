import AppKit
import Combine
import XCTest
@testable import BugNarrator

/// Provider/tracker validation workflows extracted verbatim from AppStateTests
/// (#431): AppState's delegation to the AI-provider and GitHub/Jira integration
/// controllers for API-key, repository, project, and issue-type validation. No
/// assertion changed; the AppStateHarness and mocks are shared via TestSupport.
@MainActor
final class AppStateProviderValidationTests: XCTestCase {

    func testValidateAPIKeyUpdatesValidationStateOnSuccess() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.validateAPIKey()

        XCTAssertEqual(harness.appState.apiKeyValidationState, .success("OpenAI accepted this key."))
    }

    func testValidateAPIKeyWithoutConfiguredKeyShowsFailure() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        await harness.appState.validateAPIKey()

        XCTAssertEqual(harness.appState.apiKeyValidationState, .failure(AppError.missingAPIKey.userMessage))
    }

    func testValidateOpenAICompatibleProviderBlocksMissingBaseURLBeforeNetworkCall() async {
        let harness = AppStateHarness(apiKey: "enterprise-token")
        defer { harness.cleanup() }

        harness.settingsStore.aiProvider = .openAICompatible

        await harness.appState.validateAPIKey()

        XCTAssertEqual(
            harness.appState.apiKeyValidationState,
            .failure("Choose a non-default API base URL for the OpenAI-Compatible provider.")
        )
        let validationCallCount = await harness.transcriptionClient.validationCallCount
        XCTAssertEqual(validationCallCount, 0)
    }

    func testValidateLocalCompatibleProviderUsesEmptyCredentialAndLocalBaseURLWhenSetupIsReady() async {
        let harness = AppStateHarness(apiKey: "")
        defer { harness.cleanup() }

        harness.settingsStore.aiProvider = .localCompatible
        harness.settingsStore.openAIBaseURL = "http://localhost:1234/v1"
        harness.settingsStore.preferredModel = "whisper-large-v3"
        harness.settingsStore.issueExtractionModel = "llama3.1:8b"

        await harness.appState.validateAPIKey()

        XCTAssertEqual(
            harness.appState.apiKeyValidationState,
            .success("The local-compatible provider accepted this configuration.")
        )
        let validationCallCount = await harness.transcriptionClient.validationCallCount
        let validationKeys = await harness.transcriptionClient.requestedValidationAPIKeys
        let validationBaseURLs = await harness.transcriptionClient.requestedValidationBaseURLs
        XCTAssertEqual(validationCallCount, 1)
        XCTAssertEqual(validationKeys, [""])
        XCTAssertEqual(validationBaseURLs.map(\.absoluteString), ["http://localhost:1234/v1"])
    }

    func testValidateGitHubConfigurationUpdatesValidationStateOnSuccess() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        harness.settingsStore.githubRepositoryOwner = "acme"
        harness.settingsStore.githubRepositoryName = "bugnarrator"
        harness.settingsStore.githubRepositoryID = "R_kgDOFixture"

        await harness.appState.validateGitHubConfiguration()

        XCTAssertEqual(
            harness.appState.gitHubValidationState,
            .success("GitHub accepted this token for acme/bugnarrator.")
        )
    }

    func testLoadGitHubRepositoriesPopulatesPickerOptions() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.githubToken = "fixture-github-token"
        await harness.exportService.setGitHubRepositories(
            [
                GitHubRepositoryOption(owner: "acme", name: "bugnarrator", description: "Main app"),
                GitHubRepositoryOption(owner: "acme", name: "internal-tools", description: nil)
            ]
        )

        await harness.appState.loadGitHubRepositories()

        XCTAssertEqual(
            harness.appState.gitHubRepositories,
            [
                GitHubRepositoryOption(owner: "acme", name: "bugnarrator", description: "Main app"),
                GitHubRepositoryOption(owner: "acme", name: "internal-tools", description: nil)
            ]
        )
        XCTAssertEqual(
            harness.appState.gitHubValidationState,
            .success("Loaded 2 GitHub repositories where this token can create issues.")
        )
    }

    func testValidateJiraConfigurationWithoutConfiguredFieldsShowsFailure() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .failure(AppError.exportConfigurationMissing("Jira project discovery requires a base URL, email, and API token.").userMessage)
        )
    }

    func testValidateJiraConfigurationLoadsProjectsBeforeProjectSelection() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "https://digitaltransformation-csra.atlassian.net/"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(
            harness.appState.jiraProjects,
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        XCTAssertEqual(harness.appState.jiraIssueTypes, [])
        XCTAssertEqual(harness.settingsStore.jiraProjectID, "")
        XCTAssertEqual(harness.settingsStore.jiraIssueTypeID, "")
        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .success("Loaded 2 Jira projects. Choose a project to load issue types.")
        )
    }

    func testSelectJiraProjectLoadsIssueTypesOnlyAfterExplicitRefresh() async throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        await harness.exportService.setJiraIssueTypes(
            [JiraIssueTypeOption(id: "10001", name: "Task")],
            for: "UCAP"
        )

        await harness.appState.validateJiraConfiguration()

        let selectedProject = try XCTUnwrap(harness.appState.jiraProjects.first(where: { $0.key == "UCAP" }))
        harness.appState.selectJiraProject(projectID: selectedProject.projectID)

        XCTAssertEqual(harness.settingsStore.jiraProjectKey, "UCAP")
        XCTAssertEqual(harness.appState.jiraIssueTypes, [])
        let fetchCountBeforeRefresh = await harness.exportService.jiraIssueTypeFetchCount()
        XCTAssertEqual(fetchCountBeforeRefresh, 0)

        await harness.appState.refreshJiraIssueTypesForSelectedProject()

        XCTAssertEqual(
            harness.appState.jiraIssueTypes,
            [JiraIssueTypeOption(id: "10001", name: "Task")]
        )
        let fetchCountAfterRefresh = await harness.exportService.jiraIssueTypeFetchCount()
        XCTAssertEqual(fetchCountAfterRefresh, 1)
    }

    func testValidateJiraConfigurationLoadsProjectsAndIssueTypes() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraIssueType = "Task"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        await harness.exportService.setJiraIssueTypes(
            [
                JiraIssueTypeOption(id: "10002", name: "Bug"),
                JiraIssueTypeOption(id: "10001", name: "Task")
            ],
            for: "UCAP"
        )

        harness.settingsStore.jiraProjectKey = "UCAP"

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(
            harness.appState.jiraProjects,
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        XCTAssertEqual(
            harness.appState.jiraIssueTypes,
            [
                JiraIssueTypeOption(id: "10002", name: "Bug"),
                JiraIssueTypeOption(id: "10001", name: "Task")
            ]
        )
        XCTAssertEqual(harness.settingsStore.jiraProjectKey, "UCAP")
        XCTAssertEqual(harness.settingsStore.jiraIssueType, "Task")
        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .success("Loaded 2 Jira projects. UCAP - Unified Claims Access Portal is ready to export as Task.")
        )
    }

    func testValidateJiraConfigurationFlagsSavedIssueTypeThatIsNoLongerAllowed() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraProjectKey = "UCAP"
        harness.settingsStore.jiraIssueType = "Task"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        await harness.exportService.setJiraIssueTypes(
            [
                JiraIssueTypeOption(id: "10002", name: "Bug")
            ],
            for: "UCAP"
        )

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(harness.settingsStore.jiraIssueType, "Task")
        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .failure("Project UCAP - Unified Claims Access Portal does not allow issue type Task. Choose one of the available issue types.")
        )
    }

    func testValidateJiraConfigurationDoesNotRetargetUnavailableSavedProject() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraProjectKey = "LEGACY"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(harness.settingsStore.jiraProjectKey, "LEGACY")
        XCTAssertEqual(harness.appState.jiraIssueTypes, [])
        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .failure("Loaded 2 Jira projects, but the saved project LEGACY is no longer available. Choose a project from the list.")
        )
    }

    func testRefreshJiraIssueTypesAppliesLatestProjectAfterRapidSwitching() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraProjectKey = "OPS"
        await harness.exportService.setJiraProjects(
            [
                JiraProjectOption(key: "OPS", name: "Operations Support"),
                JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")
            ]
        )
        await harness.appState.validateJiraConfiguration()

        await harness.exportService.setJiraIssueTypes(
            [JiraIssueTypeOption(id: "20001", name: "Story")],
            for: "OPS"
        )
        await harness.exportService.setJiraIssueTypes(
            [JiraIssueTypeOption(id: "10001", name: "Task")],
            for: "UCAP"
        )
        await harness.appState.validateJiraConfiguration()
        await harness.exportService.setSuspendJiraIssueTypeFetch(true)

        await MainActor.run {
            harness.settingsStore.jiraProjectKey = "UCAP"
        }

        let firstRefresh = Task {
            await harness.appState.refreshJiraIssueTypesForSelectedProject()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        await MainActor.run {
            harness.settingsStore.jiraProjectKey = "OPS"
        }

        let secondRefresh = Task {
            await harness.appState.refreshJiraIssueTypesForSelectedProject()
        }

        await harness.exportService.resumeJiraIssueTypeFetch(
            for: "UCAP",
            with: .success([JiraIssueTypeOption(id: "10001", name: "Task")])
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        await harness.exportService.resumeJiraIssueTypeFetch(
            for: "OPS",
            with: .success([JiraIssueTypeOption(id: "20001", name: "Story")])
        )

        _ = await firstRefresh.result
        _ = await secondRefresh.result

        XCTAssertEqual(
            harness.appState.jiraIssueTypes,
            [JiraIssueTypeOption(id: "20001", name: "Story")]
        )
        XCTAssertEqual(harness.settingsStore.jiraProjectKey, "OPS")
    }

    func testValidateJiraConfigurationKeepsLastKnownMetadataOnTransientIssueTypeFailure() async {
        let harness = AppStateHarness()
        defer { harness.cleanup() }

        harness.settingsStore.jiraBaseURL = "digitaltransformation-csra.atlassian.net"
        harness.settingsStore.jiraEmail = "alan.deffenderfer@gdit.com"
        harness.settingsStore.jiraAPIToken = "fixture-jira-token"
        harness.settingsStore.jiraProjectKey = "UCAP"
        harness.settingsStore.jiraIssueType = "Task"
        await harness.exportService.setJiraProjects([JiraProjectOption(key: "UCAP", name: "Unified Claims Access Portal")])
        await harness.exportService.setJiraIssueTypes([JiraIssueTypeOption(id: "10001", name: "Task")], for: "UCAP")

        await harness.appState.validateJiraConfiguration()
        await harness.exportService.setJiraIssueTypesError(AppError.exportFailure("Transient Jira outage"))

        await harness.appState.validateJiraConfiguration()

        XCTAssertEqual(
            harness.appState.jiraIssueTypes,
            [JiraIssueTypeOption(id: "10001", name: "Task")]
        )
        XCTAssertTrue(harness.appState.jiraIssueTypeMetadataIsStale)
        XCTAssertEqual(
            harness.appState.jiraValidationState,
            .failure(AppError.exportFailure("Transient Jira outage").userMessage)
        )
    }
}
