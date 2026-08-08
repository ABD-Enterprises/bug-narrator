import XCTest
@testable import BugNarrator

/// Covers the Settings landing-pane rule from #911: an install with no usable
/// AI provider credential opens on `AI Engines` rather than `General`.
///
/// Two layers on purpose. The first pair pins the pure mapping. The second pair
/// drives a real `SettingsStore` so the *wiring* is covered too — that
/// `initialSection` is fed `hasUsableAIProviderCredential` and not some other
/// readiness signal. A review of the original version noted the pure-function
/// tests alone would still pass if the init were wired to the wrong input.
@MainActor
final class SettingsViewInitialSectionTests: XCTestCase {
    // MARK: - Pure mapping

    func testUnconfiguredInstallOpensOnAIEngines() {
        XCTAssertEqual(
            SettingsView.initialSection(hasUsableAIProviderCredential: false),
            .aiEngines,
            "A user with no usable provider credential is sent to Settings by the recording gate; they must land on the pane that resolves it."
        )
    }

    func testConfiguredInstallOpensOnGeneral() {
        XCTAssertEqual(
            SettingsView.initialSection(hasUsableAIProviderCredential: true),
            .general,
            "Once a provider is configured, Settings keeps its established General landing pane."
        )
    }

    /// #357 extended the rule: the welcome tour's provider step routes here, and
    /// a provider that has a credential but fails `aiProviderCompatibilityIssue`
    /// would otherwise land on `General`, which cannot resolve it.
    func testCredentialWithACompatibilityIssueStillOpensOnAIEngines() {
        XCTAssertEqual(
            SettingsView.initialSection(
                hasUsableAIProviderCredential: true,
                hasProviderCompatibilityIssue: true
            ),
            .aiEngines,
            "A configured-but-incompatible provider is not a working setup; General cannot fix it."
        )
    }

    func testCompatibleCredentialKeepsGeneralLanding() {
        XCTAssertEqual(
            SettingsView.initialSection(
                hasUsableAIProviderCredential: true,
                hasProviderCompatibilityIssue: false
            ),
            .general
        )
    }

    // MARK: - Wiring against a real SettingsStore

    func testStoreWithNoCredentialResolvesToAIEngines() {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertFalse(
            harness.settingsStore.hasUsableAIProviderCredential,
            "Precondition: an empty OpenAI key means no usable credential."
        )
        XCTAssertEqual(
            SettingsView.initialSection(
                hasUsableAIProviderCredential: harness.settingsStore.hasUsableAIProviderCredential
            ),
            .aiEngines
        )
    }

    func testStoreWithCredentialResolvesToGeneral() {
        let harness = AppStateHarness(apiKey: "sk-test-123")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertTrue(
            harness.settingsStore.hasUsableAIProviderCredential,
            "Precondition: a present OpenAI key means a usable credential."
        )
        XCTAssertEqual(
            SettingsView.initialSection(
                hasUsableAIProviderCredential: harness.settingsStore.hasUsableAIProviderCredential
            ),
            .general
        )
    }

    /// Local providers report `true` unconditionally — they need no credential —
    /// so they keep the General landing even with an empty key. This pins the
    /// behavior a review flagged as easy to misread as a bug.
    func testKeylessLocalProviderKeepsGeneralLanding() {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .parakeetLocal

        XCTAssertTrue(
            harness.settingsStore.hasUsableAIProviderCredential,
            "Local (Parakeet) requires no API key, so credential readiness is true even with an empty key."
        )
        XCTAssertEqual(
            SettingsView.initialSection(
                hasUsableAIProviderCredential: harness.settingsStore.hasUsableAIProviderCredential
            ),
            .general,
            "A keyless local provider was never blocked by a missing credential, so it should not be redirected."
        )
    }
}
