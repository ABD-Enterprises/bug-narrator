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

    // MARK: - keychainLocked placeholders for the token slots (#1105)
    // The OpenAI slot's locked placeholder is pinned in SettingsStoreTests; the
    // token slots use a different word ("token", not "key") and were not.

    func test_maskedGitHubToken_keychainLocked_returnsSavedTokenLocked() throws {
        let (store, cleanup) = makeLockedStore(key: "BugNarrator.GitHub::github-token", value: "ghp_locked")
        defer { cleanup() }

        XCTAssertEqual(store.githubTokenPersistenceState, .keychainLocked)
        XCTAssertEqual(store.maskedGitHubToken, "Saved token locked")
    }

    func test_maskedJiraAPIToken_keychainLocked_returnsSavedTokenLocked() throws {
        let (store, cleanup) = makeLockedStore(key: "BugNarrator.Jira::jira-api-token", value: "jira_locked")
        defer { cleanup() }

        XCTAssertEqual(store.jiraTokenPersistenceState, .keychainLocked)
        XCTAssertEqual(store.maskedJiraAPIToken, "Saved token locked")
    }

    // MARK: - suffix length

    func test_mask_neverShowsMoreThanFourCharacters() throws {
        let harness = AppStateHarness(apiKey: "sk-live-abcdefghijklmnop")
        harness.settingsStore.aiProvider = .openAI

        let masked = harness.settingsStore.maskedAPIKey
        XCTAssertTrue(masked.hasPrefix("••••••••"))
        XCTAssertEqual(masked.count, 8 + 4)
        XCTAssertFalse(masked.contains("sk-live"))
    }

    func test_mask_shortSecretIsShownInFullAfterTheBullets() throws {
        // Pinned, not endorsed: a secret of four characters or fewer has nothing
        // left to hide once the last four are shown, so "••••••••abcd" IS the
        // whole secret. Real credentials are far longer; if a clamp is ever
        // wanted, this is the test that will need to change.
        let harness = AppStateHarness(apiKey: "abcd")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.maskedAPIKey, "••••••••abcd")
    }

    private func makeLockedStore(key: String, value: String) -> (SettingsStore, () -> Void) {
        let suiteName = "BugNarrator-DisplayMaskTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let keychain = MockKeychainService()
        keychain.values[key] = value
        keychain.interactionRequiredKeys = [key]
        let store = makeIsolatedSettingsStore(defaults: defaults, keychainService: keychain)
        return (store, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
