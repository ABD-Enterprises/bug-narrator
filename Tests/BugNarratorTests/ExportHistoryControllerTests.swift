import XCTest
@testable import BugNarrator

@MainActor
final class ExportHistoryControllerTests: XCTestCase {
    func testRefreshLoadsReceiptsFromExportService() async {
        let exportService = MockExportService()
        let controller = ExportHistoryController(exportService: exportService)
        let receipt = makeReceipt()
        await exportService.setExportReceipts([receipt])

        await controller.refreshExportHistory()

        XCTAssertEqual(controller.exportHistory, [receipt])
    }

    func testRefreshClearsStaleReceiptsWhenExportServiceFails() async {
        let staleReceipt = makeReceipt(fingerprint: "stale")
        let controller = ExportHistoryController(
            exportService: FailingExportHistoryService(),
            exportHistory: [staleReceipt]
        )

        await controller.refreshExportHistory()

        XCTAssertEqual(controller.exportHistory, [])
    }

    private func makeReceipt(fingerprint: String = "github:fixture") -> ExportReceipt {
        ExportReceipt(
            fingerprint: fingerprint,
            sourceIssueID: UUID(),
            destination: .github,
            targetIdentity: "deffenda/bug-narrator",
            state: .succeeded,
            remoteIdentifier: "#42",
            remoteURL: URL(string: "https://github.com/deffenda/bug-narrator/issues/42"),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private actor FailingExportHistoryService: IssueExporting {
    func fetchGitHubRepositories(token: String) async throws -> [GitHubRepositoryOption] { [] }

    func fetchJiraProjects(_ configuration: JiraConnectionConfiguration) async throws -> [JiraProjectOption] { [] }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        []
    }

    func validateGitHubConfiguration(_ configuration: GitHubExportConfiguration) async throws {}

    func validateJiraConfiguration(_ configuration: JiraExportConfiguration) async throws {}

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        IssueExportReview(destination: .github, sessionID: session.id, items: [])
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExportReview {
        IssueExportReview(destination: .jira, sessionID: session.id, items: [])
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        []
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        []
    }

    func exportHistory() async throws -> [ExportReceipt] {
        throw NSError(domain: "ExportHistoryControllerTests", code: 1)
    }
}
