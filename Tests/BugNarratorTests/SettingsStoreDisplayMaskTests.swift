import XCTest
@testable import BugNarrator

@MainActor
final class SettingsStoreDisplayMaskTests: XCTestCase {
    // MARK: - maskedAPIKey

    func test_maskedAPIKey_emptyState_returnsNoKeySavedPlaceholder() throws {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.maskedAPIKey, "No key saved")
    }

    func test_maskedAPIKey_pendingSaveState_returnsMaskedSuffix() throws {
        let harness = AppStateHarness(apiKey: "sk-test-1234")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.maskedAPIKey, "••••••••1234")
    }

    // MARK: - maskedSelectedAIProviderCredential

    func test_maskedSelectedAIProviderCredential_emptyState_returnsNoKeySavedPlaceholder() throws {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.maskedSelectedAIProviderCredential, "No key saved")
    }

    func test_maskedSelectedAIProviderCredential_pendingSaveState_returnsMaskedSuffix() throws {
        let harness = AppStateHarness(apiKey: "sk-test-1234")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.maskedSelectedAIProviderCredential, "••••••••1234")
    }

    // MARK: - maskedGitHubToken

    func test_maskedGitHubToken_emptyState_returnsNoTokenSavedPlaceholder() throws {
        let harness = AppStateHarness()
        // githubToken defaults to "" via SettingsStore init → .empty

        XCTAssertEqual(harness.settingsStore.maskedGitHubToken, "No token saved")
    }

    func test_maskedGitHubToken_pendingSaveState_returnsMaskedSuffix() throws {
        let harness = AppStateHarness()
        harness.settingsStore.githubToken = "ghp_testtoken1234"

        XCTAssertEqual(harness.settingsStore.maskedGitHubToken, "••••••••1234")
    }

    // MARK: - maskedJiraAPIToken

    func test_maskedJiraAPIToken_emptyState_returnsNoTokenSavedPlaceholder() throws {
        let harness = AppStateHarness()
        // jiraAPIToken defaults to "" → .empty

        XCTAssertEqual(harness.settingsStore.maskedJiraAPIToken, "No token saved")
    }

    func test_maskedJiraAPIToken_pendingSaveState_returnsMaskedSuffix() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraAPIToken = "atl_testtoken1234"

        XCTAssertEqual(harness.settingsStore.maskedJiraAPIToken, "••••••••1234")
    }
}
