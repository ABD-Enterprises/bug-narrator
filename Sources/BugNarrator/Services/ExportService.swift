import Foundation

actor ExportService: IssueExporting {
    private let gitHubProvider: GitHubExportProvider
    private let jiraProvider: JiraExportProvider
    private let similarIssueReviewService: SimilarIssueReviewService

    init(
        gitHubProvider: GitHubExportProvider = GitHubExportProvider(),
        jiraProvider: JiraExportProvider = JiraExportProvider(),
        similarIssueReviewService: SimilarIssueReviewService = SimilarIssueReviewService()
    ) {
        self.gitHubProvider = gitHubProvider
        self.jiraProvider = jiraProvider
        self.similarIssueReviewService = similarIssueReviewService
    }

    func fetchGitHubRepositories(
        token: String
    ) async throws -> [GitHubRepositoryOption] {
        try await gitHubProvider.fetchRepositories(token: token)
    }

    func fetchJiraProjects(
        _ configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        try await jiraProvider.fetchProjects(configuration: configuration)
    }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        try await jiraProvider.fetchIssueTypes(for: projectKey, projectID: projectID, configuration: configuration)
    }

    func validateGitHubConfiguration(
        _ configuration: GitHubExportConfiguration
    ) async throws {
        try await gitHubProvider.validate(configuration: configuration)
    }

    func validateJiraConfiguration(
        _ configuration: JiraExportConfiguration
    ) async throws {
        try await jiraProvider.validate(configuration: configuration)
    }

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .github,
            apiKey: apiKey,
            model: model,
            apiBaseURL: apiBaseURL
        ) { issue in
            try await self.gitHubProvider.findOpenIssues(matching: issue, configuration: configuration)
        }
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        try await similarIssueReviewService.prepareReview(
            issues: issues,
            session: session,
            destination: .jira,
            apiKey: apiKey,
            model: model,
            apiBaseURL: apiBaseURL
        ) { issue in
            try await self.jiraProvider.findOpenIssues(matching: issue, configuration: configuration)
        }
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        try await gitHubProvider.export(issues: issues, session: session, configuration: configuration)
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        try await jiraProvider.export(issues: issues, session: session, configuration: configuration)
    }

    func exportHistory() async throws -> [ExportReceipt] {
        try await ExportReceiptStore().allReceipts()
    }
}
