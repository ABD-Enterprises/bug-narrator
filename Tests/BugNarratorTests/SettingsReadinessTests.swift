import XCTest
@testable import BugNarrator

/// SettingsReadiness is the pure mapping from store state to the status the
/// Settings UI shows. It had zero coverage — including `openAIReadiness`, which
/// is where the UI learns that the keyless local-server default is *not* ready
/// when the server is unreachable (#1026). Every store here is built through
/// `makeIsolatedSettingsStore`, so nothing can reach a real socket or keychain.
final class SettingsReadinessTests: XCTestCase {

    // MARK: - credentialStatus: every persistence state x value present/absent

    func testCredentialStatusCoversEveryPersistenceState() {
        let cases: [(APIKeyPersistenceState, Bool, SettingsReadinessStatus)] = [
            (.pendingSave, true, .pendingSave),
            (.pendingSave, false, .pendingSave),
            (.keychainLocked, true, .locked),
            (.keychainLocked, false, .locked),
            (.empty, true, .needsSetup),
            (.empty, false, .needsSetup),
            (.keychain, true, .ready),
            (.keychain, false, .needsSetup),
            (.sessionOnly, true, .ready),
            (.sessionOnly, false, .needsSetup),
        ]
        for (state, present, expected) in cases {
            XCTAssertEqual(
                SettingsReadiness.credentialStatus(valueIsPresent: present, persistenceState: state),
                expected,
                "credentialStatus(valueIsPresent: \(present), persistenceState: \(state))"
            )
        }
    }

    // MARK: - prerequisiteStatus: pendingSave/locked win regardless of readiness

    func testPrerequisiteStatusCoversEveryPersistenceState() {
        let cases: [(APIKeyPersistenceState, Bool, SettingsReadinessStatus)] = [
            (.pendingSave, true, .pendingSave),
            (.pendingSave, false, .pendingSave),
            (.keychainLocked, true, .locked),
            (.keychainLocked, false, .locked),
            (.empty, true, .ready),
            (.empty, false, .needsSetup),
            (.keychain, true, .ready),
            (.keychain, false, .needsSetup),
            (.sessionOnly, true, .ready),
            (.sessionOnly, false, .needsSetup),
        ]
        for (state, ready, expected) in cases {
            XCTAssertEqual(
                SettingsReadiness.prerequisiteStatus(for: state, isReady: ready),
                expected,
                "prerequisiteStatus(for: \(state), isReady: \(ready))"
            )
        }
    }

    // MARK: - openAIReadiness: keyed provider

    func testKeyedProviderWithNoKeyNeedsSetup() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }
        store.aiProvider = .openAI

        XCTAssertEqual(SettingsReadiness.openAIReadiness(store), .needsSetup)
    }

    func testKeyedProviderWithFreshlyEnteredKeyIsPendingSave() {
        // A secret set in-session sits in pendingSave until committed, and the
        // readiness surface must say so rather than report ready or needsSetup.
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }
        store.aiProvider = .openAI
        store.apiKey = "sk-fixture"

        XCTAssertEqual(store.apiKeyPersistenceState, .pendingSave)
        XCTAssertEqual(SettingsReadiness.openAIReadiness(store), .pendingSave)
    }

    // MARK: - openAIReadiness: keyless provider follows reachability, not credentials

    func testLocalProviderIsReadyWithNoKeyWhenServerIsReachable() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }
        store.aiProvider = .parakeetLocal

        XCTAssertFalse(store.hasAPIKey, "precondition: no key entered")
        XCTAssertEqual(SettingsReadiness.openAIReadiness(store), .ready)
    }

    func testLocalProviderNeedsSetupWhenServerIsUnreachable() {
        // The keyless default must not read as ready when nothing is listening.
        // Before #1026 readiness was configuration-only and reported ready here.
        let (store, cleanup) = makeStore(reachable: false)
        defer { cleanup() }
        store.aiProvider = .parakeetLocal

        XCTAssertEqual(SettingsReadiness.openAIReadiness(store), .needsSetup)
    }

    func testLocalProviderIgnoresAStrayAPIKey() {
        // A leftover key from a previous keyed provider must not make an
        // unreachable local server look ready.
        let (store, cleanup) = makeStore(reachable: false)
        defer { cleanup() }
        store.aiProvider = .parakeetLocal
        store.apiKey = "sk-leftover"

        XCTAssertEqual(SettingsReadiness.openAIReadiness(store), .needsSetup)
    }

    // MARK: - gitHubReadiness

    func testGitHubReadinessNeedsSetupWhenUnconfigured() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }

        XCTAssertNil(store.githubExportConfiguration)
        XCTAssertEqual(SettingsReadiness.gitHubReadiness(store), .needsSetup)
    }

    func testGitHubReadinessIsPendingSaveWhileTokenIsUncommitted() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }
        store.githubToken = "ghp_fixture"

        XCTAssertEqual(store.githubTokenPersistenceState, .pendingSave)
        XCTAssertEqual(SettingsReadiness.gitHubReadiness(store), .pendingSave)
    }

    // MARK: - jiraReadiness

    func testJiraReadinessNeedsSetupWhenUnconfigured() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }

        XCTAssertNil(store.jiraExportConfiguration)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .needsSetup)
    }

    func testJiraReadinessIsPendingSaveWhenOnlyTheEmailIsUncommitted() {
        let (store, cleanup) = makeStore(reachable: true)
        defer { cleanup() }
        store.jiraEmail = "you@example.com"

        XCTAssertEqual(store.jiraEmailPersistenceState, .pendingSave)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .pendingSave)
    }

    // MARK: - the .ready branches, which a "return .needsSetup" stub would silently pass without

    func testGitHubReadinessIsReadyWhenTokenIsCommittedAndRepositoryIsSet() {
        // The token must already be IN the keychain: a token set in-session sits in
        // pendingSave and short-circuits before .ready is ever reachable.
        let keychain = MockKeychainService()
        keychain.values["BugNarrator.GitHub::github-token"] = "ghp_committed"
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }
        store.githubRepositoryOwner = "acme"
        store.githubRepositoryName = "widgets"

        XCTAssertEqual(store.githubTokenPersistenceState, .keychain)
        XCTAssertNotNil(store.githubExportConfiguration)
        XCTAssertEqual(SettingsReadiness.gitHubReadiness(store), .ready)
    }

    func testJiraReadinessIsReadyWhenConnectionProjectAndIssueTypeAreSet() {
        let keychain = MockKeychainService()
        keychain.values["BugNarrator.Jira::jira-email"] = "you@example.com"
        keychain.values["BugNarrator.Jira::jira-api-token"] = "jira-committed"
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }
        store.jiraBaseURL = "https://acme.atlassian.net"
        store.jiraProjectKey = "FM"
        store.jiraIssueType = "Bug"

        XCTAssertEqual(store.jiraTokenPersistenceState, .keychain)
        XCTAssertNotNil(store.jiraExportConfiguration)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .ready)
    }

    // MARK: - jiraReadiness checks BOTH secrets on each side of its ||; test each side alone

    func testJiraReadinessIsPendingSaveWhenOnlyTheTokenIsUncommitted() {
        // Email committed, token freshly entered: the right-hand operand of the
        // pendingSave check must fire on its own.
        let keychain = MockKeychainService()
        keychain.values["BugNarrator.Jira::jira-email"] = "you@example.com"
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }
        store.jiraAPIToken = "jira-fresh"

        XCTAssertEqual(store.jiraEmailPersistenceState, .keychain)
        XCTAssertEqual(store.jiraTokenPersistenceState, .pendingSave)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .pendingSave)
    }

    func testJiraReadinessIsLockedWhenOnlyTheEmailNeedsInteraction() {
        // Token readable, email locked: the left-hand operand of the locked check
        // must fire on its own.
        let keychain = MockKeychainService()
        let emailKey = "BugNarrator.Jira::jira-email"
        keychain.values[emailKey] = "you@example.com"
        keychain.values["BugNarrator.Jira::jira-api-token"] = "jira-committed"
        keychain.interactionRequiredKeys = [emailKey]
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }

        XCTAssertEqual(store.jiraEmailPersistenceState, .keychainLocked)
        XCTAssertEqual(store.jiraTokenPersistenceState, .keychain)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .locked)
    }

    func testJiraReadinessPrefersPendingSaveOverLockedWhenSecretsDisagree() {
        // Email locked in the keychain, token just typed: pendingSave must win.
        // The user's most recent action is the unsaved token, and telling them
        // "keychain locked" instead would hide that it has not been saved yet.
        // Pins guard ORDER, which no single-state test can — swapping the two
        // checks in jiraReadiness passes every other test in this file.
        let keychain = MockKeychainService()
        let emailKey = "BugNarrator.Jira::jira-email"
        keychain.values[emailKey] = "you@example.com"
        keychain.interactionRequiredKeys = [emailKey]
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }
        store.jiraAPIToken = "jira-fresh"

        XCTAssertEqual(store.jiraEmailPersistenceState, .keychainLocked)
        XCTAssertEqual(store.jiraTokenPersistenceState, .pendingSave)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .pendingSave)
    }

    // MARK: - locked keychain: GitHub and Jira report .locked, not .needsSetup

    func testGitHubReadinessIsLockedWhenTheKeychainNeedsInteraction() {
        // A token exists but the keychain will not release it without a prompt.
        // The UI must say "locked", not "needs setup" — the user has done setup.
        let keychain = MockKeychainService()
        let key = "BugNarrator.GitHub::github-token"
        keychain.values[key] = "ghp_stored"
        keychain.interactionRequiredKeys = [key]
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }

        XCTAssertEqual(store.githubTokenPersistenceState, .keychainLocked)
        XCTAssertEqual(SettingsReadiness.gitHubReadiness(store), .locked)
    }

    func testJiraReadinessIsLockedWhenOnlyTheTokenNeedsInteraction() {
        let keychain = MockKeychainService()
        let key = "BugNarrator.Jira::jira-api-token"
        keychain.values[key] = "jira-stored"
        keychain.interactionRequiredKeys = [key]
        let (store, cleanup) = makeStore(reachable: true, keychain: keychain)
        defer { cleanup() }

        XCTAssertEqual(store.jiraTokenPersistenceState, .keychainLocked)
        XCTAssertEqual(SettingsReadiness.jiraReadiness(store), .locked)
    }

    // MARK: - Helpers

    private func makeStore(
        reachable: Bool,
        keychain: MockKeychainService = MockKeychainService()
    ) -> (SettingsStore, () -> Void) {
        let suiteName = "BugNarrator-SettingsReadinessTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = makeIsolatedSettingsStore(
            defaults: defaults,
            keychainService: keychain,
            localProviderReachabilityProbe: { _ in reachable }
        )
        return (store, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
