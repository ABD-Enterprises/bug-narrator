import Foundation

extension AppState {
    func jiraIssueTypes(for target: JiraIssueExportTarget) -> [JiraIssueTypeOption] {
        trackerIntegration.jiraIssueTypes(for: target)
    }

    func validateGitHubConfiguration() async {
        await trackerIntegration.validateGitHubConfiguration()
    }

    func loadGitHubRepositories() async {
        await trackerIntegration.loadGitHubRepositories()
    }

    func validateJiraConfiguration() async {
        await trackerIntegration.validateJiraConfiguration()
    }

    func selectJiraProject(projectID: String) {
        trackerIntegration.selectJiraProject(projectID: projectID)
    }

    func refreshJiraIssueTypesForSelectedProject() async {
        await trackerIntegration.refreshJiraIssueTypesForSelectedProject()
    }

    func loadJiraIssueTypes(forProjectID projectID: String) async {
        await trackerIntegration.loadJiraIssueTypes(forProjectID: projectID)
    }
}
