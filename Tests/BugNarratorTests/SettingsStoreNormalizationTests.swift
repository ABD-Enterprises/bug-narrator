import XCTest
@testable import BugNarrator

@MainActor
final class SettingsStoreNormalizationTests: XCTestCase {
    // MARK: - Whitespace-only input → empty string

    func test_normalizedGitHubRepositoryOwner_whitespaceOnly_returnsEmpty() throws {
        let harness = AppStateHarness()
        harness.settingsStore.githubRepositoryOwner = "   \n\t  "

        XCTAssertEqual(harness.settingsStore.normalizedGitHubRepositoryOwner, "")
    }

    func test_normalizedJiraBaseURL_whitespaceAndSlashOnly_returnsEmpty() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraBaseURL = "  //  "

        XCTAssertEqual(harness.settingsStore.normalizedJiraBaseURL, "")
    }

    func test_normalizedJiraProjectKey_whitespaceOnly_returnsEmpty() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraProjectKey = "   "

        XCTAssertEqual(harness.settingsStore.normalizedJiraProjectKey, "")
    }

    // MARK: - Leading/trailing whitespace → trimmed

    func test_normalizedGitHubRepositoryOwner_leadingTrailingWhitespace_isTrimmed() throws {
        let harness = AppStateHarness()
        harness.settingsStore.githubRepositoryOwner = "  ABD-Enterprises  "

        XCTAssertEqual(harness.settingsStore.normalizedGitHubRepositoryOwner, "ABD-Enterprises")
    }

    func test_normalizedJiraBaseURL_leadingTrailingWhitespace_isTrimmed() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraBaseURL = "  https://acme.atlassian.net  "

        XCTAssertEqual(harness.settingsStore.normalizedJiraBaseURL, "https://acme.atlassian.net")
    }

    func test_normalizedJiraProjectKey_leadingTrailingWhitespace_isTrimmed() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraProjectKey = "  bug  "

        XCTAssertEqual(harness.settingsStore.normalizedJiraProjectKey, "BUG")
    }

    // MARK: - Special-case transforms

    func test_normalizedJiraBaseURL_stripsTrailingSlash() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraBaseURL = "https://acme.atlassian.net/"

        XCTAssertEqual(harness.settingsStore.normalizedJiraBaseURL, "https://acme.atlassian.net")
    }

    func test_normalizedJiraBaseURL_stripsMultipleTrailingSlashes() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraBaseURL = "https://acme.atlassian.net///"

        XCTAssertEqual(harness.settingsStore.normalizedJiraBaseURL, "https://acme.atlassian.net")
    }

    func test_normalizedJiraProjectKey_uppercasesResult() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraProjectKey = "bugsCoolProject"

        XCTAssertEqual(harness.settingsStore.normalizedJiraProjectKey, "BUGSCOOLPROJECT")
    }
}
