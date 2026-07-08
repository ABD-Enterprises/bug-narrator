import XCTest
@testable import BugNarrator

@MainActor
final class SettingsStoreDisplayTests: XCTestCase {
    // MARK: - apiKeyStorageDescription

    func test_apiKeyStorageDescription_emptyState_returnsProviderPrompt() throws {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .openAI

        let description = harness.settingsStore.apiKeyStorageDescription

        XCTAssertTrue(
            description.contains("BugNarrator never ships with an API key."),
            "Expected empty-state prompt, got: \(description)"
        )
    }

    func test_apiKeyStorageDescription_pendingSaveState_returnsNotSavedYetMessage() throws {
        let harness = AppStateHarness(apiKey: "sk-test-123")
        harness.settingsStore.aiProvider = .openAI

        let description = harness.settingsStore.apiKeyStorageDescription

        XCTAssertEqual(
            description,
            "Not saved yet. BugNarrator will only prompt to use Keychain when you validate the key or run an action that needs it."
        )
    }

    // MARK: - selectedAIProviderCredentialStorageDescription

    func test_selectedAIProviderCredentialStorageDescription_emptyState_returnsProviderPrompt() throws {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .openAI

        let description = harness.settingsStore.selectedAIProviderCredentialStorageDescription

        XCTAssertTrue(
            description.contains("BugNarrator never ships with an API key."),
            "Expected empty-state prompt, got: \(description)"
        )
    }

    func test_selectedAIProviderCredentialStorageDescription_pendingSaveState_returnsNotSavedYetMessage() throws {
        let harness = AppStateHarness(apiKey: "sk-test-123")
        harness.settingsStore.aiProvider = .openAI

        let description = harness.settingsStore.selectedAIProviderCredentialStorageDescription

        XCTAssertEqual(
            description,
            "Not saved yet. BugNarrator will only prompt to use Keychain when you validate the key or run an action that needs it."
        )
    }

    // MARK: - githubTokenStorageDescription

    func test_githubTokenStorageDescription_emptyState_returnsPasteHint() throws {
        let harness = AppStateHarness()
        // githubToken defaults to "" via SettingsStore init → .empty

        let description = harness.settingsStore.githubTokenStorageDescription

        XCTAssertEqual(
            description,
            "Add a GitHub personal access token if you want to try the experimental GitHub Issues export."
        )
    }

    func test_githubTokenStorageDescription_pendingSaveState_returnsNotSavedYetMessage() throws {
        let harness = AppStateHarness()
        harness.settingsStore.githubToken = "ghp_testtoken"

        let description = harness.settingsStore.githubTokenStorageDescription

        XCTAssertEqual(
            description,
            "Not saved yet. BugNarrator will only prompt to use Keychain when you validate the key or run an action that needs it."
        )
    }

    // MARK: - jiraTokenStorageDescription

    func test_jiraTokenStorageDescription_emptyState_returnsPasteHint() throws {
        let harness = AppStateHarness()
        // jiraAPIToken defaults to "" via SettingsStore init → .empty

        let description = harness.settingsStore.jiraTokenStorageDescription

        XCTAssertEqual(
            description,
            "Add Jira Cloud credentials if you want to try the experimental Jira export."
        )
    }

    func test_jiraTokenStorageDescription_pendingSaveState_returnsNotSavedYetMessage() throws {
        let harness = AppStateHarness()
        harness.settingsStore.jiraAPIToken = "atl_testtoken"

        let description = harness.settingsStore.jiraTokenStorageDescription

        XCTAssertEqual(
            description,
            "Not saved yet. BugNarrator will only prompt to use Keychain when you validate the key or run an action that needs it."
        )
    }
}
