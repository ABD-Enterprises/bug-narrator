import Foundation
import XCTest
@testable import BugNarrator

/// #357 `done_when`: "Step-gating and completion logic live in pure, testable
/// helpers with unit tests covering: fresh install, partially configured,
/// fully configured, and skipped."
final class OnboardingFlowTests: XCTestCase {
    private func snapshot(
        credential: Bool = false,
        compatible: Bool = true,
        microphone: Bool = false,
        hotkeys: Bool = false
    ) -> OnboardingSnapshot {
        OnboardingSnapshot(
            hasUsableAIProviderCredential: credential,
            providerConfigurationIsCompatible: compatible,
            microphoneAuthorized: microphone,
            hasAnyCaptureHotkeyAssigned: hotkeys
        )
    }

    // MARK: - Fresh install

    func testFreshInstallStartsAtTheProviderStep() {
        let fresh = snapshot()

        XCTAssertEqual(OnboardingFlow.firstIncompleteStep(in: fresh), .provider)
        XCTAssertFalse(OnboardingFlow.isFullyConfigured(fresh))
        XCTAssertTrue(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: false,
                snapshot: fresh
            )
        )
    }

    func testFreshInstallHasNoStepComplete() {
        let fresh = snapshot()
        for step in OnboardingStep.allCases {
            XCTAssertFalse(OnboardingFlow.isComplete(step, in: fresh), "\(step.rawValue) should be incomplete")
        }
    }

    // MARK: - Partially configured

    func testCredentialWithoutCompatibilityDoesNotCompleteTheProviderStep() {
        let broken = snapshot(credential: true, compatible: false)

        XCTAssertFalse(
            OnboardingFlow.isComplete(.provider, in: broken),
            "A credential that fails aiProviderCompatibilityIssue is not a usable setup — e.g. whisper-1 on a local provider."
        )
        XCTAssertEqual(OnboardingFlow.firstIncompleteStep(in: broken), .provider)
    }

    func testProviderDoneAdvancesToMicrophone() {
        let partial = snapshot(credential: true)
        XCTAssertTrue(OnboardingFlow.isComplete(.provider, in: partial))
        XCTAssertEqual(OnboardingFlow.firstIncompleteStep(in: partial), .microphone)
    }

    func testProviderAndMicrophoneDoneAdvancesToHotkeys() {
        let partial = snapshot(credential: true, microphone: true)
        XCTAssertEqual(OnboardingFlow.firstIncompleteStep(in: partial), .hotkeys)
        XCTAssertFalse(OnboardingFlow.isFullyConfigured(partial))
    }

    // MARK: - Fully configured

    func testFullyConfiguredHasNoNextStep() {
        let done = snapshot(credential: true, microphone: true, hotkeys: true)

        XCTAssertNil(OnboardingFlow.firstIncompleteStep(in: done))
        XCTAssertTrue(OnboardingFlow.isFullyConfigured(done))
    }

    /// An existing install upgrading into this feature must not be greeted with
    /// a setup tour it does not need.
    func testFullyConfiguredUserIsNeverGreetedEvenIfNeverOnboarded() {
        let done = snapshot(credential: true, microphone: true, hotkeys: true)

        XCTAssertFalse(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: false,
                snapshot: done
            )
        )
    }

    // MARK: - Skipped

    func testSkippingSuppressesTheFlowOnLaterLaunches() {
        let stillUnconfigured = snapshot()

        XCTAssertFalse(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: true,
                hasExistingUserState: false,
                snapshot: stillUnconfigured
            ),
            "Skipping must be durable — an unconfigured user who dismissed the tour should not be re-prompted every launch."
        )
    }

    func testSkippingDoesNotFabricateCompletion() {
        let stillUnconfigured = snapshot()

        XCTAssertFalse(
            OnboardingFlow.isFullyConfigured(stillUnconfigured),
            "Dismissing the tour must not make the app believe setup is done — the finish-setup banner (#378) still has to fire."
        )
        XCTAssertEqual(OnboardingFlow.firstIncompleteStep(in: stillUnconfigured), .provider)
    }

    // MARK: - Existing installs

    /// The regression this gate exists for. Capture hotkeys ship unbound by the
    /// 1.0.11 decision, so almost every existing install fails
    /// `isFullyConfigured` — without `hasExistingUserState`, upgrading into this
    /// feature would greet every long-time user with a setup tour.
    func testExistingUserWithRecordedSessionsIsNeverGreeted() {
        let unboundHotkeys = snapshot(credential: true, microphone: true, hotkeys: false)

        XCTAssertFalse(
            OnboardingFlow.isFullyConfigured(unboundHotkeys),
            "Precondition: unbound hotkeys alone make an install 'not fully configured'."
        )
        XCTAssertFalse(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: true,
                snapshot: unboundHotkeys
            ),
            "Someone with recorded sessions has already found their way around; they are not a first-run user."
        )
    }

    /// A stale install that never got set up is still worth onboarding — the
    /// gate is "has recorded something", not "has launched before".
    func testExistingInstallWithNoSessionsIsStillGreeted() {
        XCTAssertTrue(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: false,
                snapshot: snapshot()
            )
        )
    }

    /// Pins the *signal*, not just the rule. The launch path first read
    /// `transcriptStore.sessions`, which a partitioned store leaves empty on a
    /// cold launch while `libraryEntries` carries the history — so a user with
    /// hundreds of sessions looked brand new and got the tour. Codex found it.
    ///
    /// This reloads a real store from disk, which is the state that reproduces
    /// it, and asserts the two readings actually disagree before checking that
    /// the one the launch path uses gives the right answer.
    func testExistingHistoryIsDetectedFromLibraryEntriesNotTheLazySessionCache() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let firstStore = TranscriptStore(storageURL: storageURL)
        try firstStore.add(makeSampleTranscriptSession(index: 1))

        let reloaded = TranscriptStore(storageURL: storageURL)
        XCTAssertTrue(
            reloaded.sessions.isEmpty,
            "Precondition: the session cache loads lazily, so it is empty on a cold launch."
        )
        XCTAssertFalse(
            reloaded.libraryEntries.isEmpty,
            "Precondition: the history itself is present in libraryEntries."
        )

        XCTAssertFalse(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: !reloaded.libraryEntries.isEmpty,
                snapshot: snapshot(credential: true, microphone: true, hotkeys: false)
            ),
            "A returning user with stored sessions and unbound hotkeys must not be greeted."
        )
        XCTAssertTrue(
            OnboardingFlow.shouldPresentOnLaunch(
                hasCompletedFirstRunOnboarding: false,
                hasExistingUserState: !reloaded.sessions.isEmpty,
                snapshot: snapshot(credential: true, microphone: true, hotkeys: false)
            ),
            "Documents the defect: reading the lazy cache would greet that same user."
        )
    }

    /// The tour and the What's New sheet (#386) must never open on the same
    /// launch.
    ///
    /// The first version of this test asserted `!(tour && changelog)` while
    /// feeding the same synthetic Boolean to both gates and a fresh defaults
    /// suite — so it never reached the `lastShownChangelogVersion` branch, and
    /// passed for the wrong reason. Codex found the launch state it missed: a
    /// pre-#357 user who saw the changelog (a version is recorded), then
    /// deleted all local data (no user state), then upgraded. Both gates say
    /// yes there. The exclusivity is now enforced by `launchPresentation`
    /// rather than argued from the gates, and this drives that case directly.
    func testBothGatesSayingYesStillOpensOnlyTheTour() {
        let suiteName = "BugNarrator-OnboardingChangelogExclusivity-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        store.markChangelogShown(version: "1.0.41")

        let changelog = store.shouldAutoShowChangelog(currentVersion: "1.0.42", hasExistingUserState: false)
        let tour = OnboardingFlow.shouldPresentOnLaunch(
            hasCompletedFirstRunOnboarding: false,
            hasExistingUserState: false,
            snapshot: snapshot()
        )

        XCTAssertTrue(changelog, "Precondition: a recorded older version means the changelog wants to show.")
        XCTAssertTrue(tour, "Precondition: an unconfigured install with no sessions wants the tour.")
        XCTAssertEqual(
            OnboardingFlow.launchPresentation(shouldPresentWelcome: tour, shouldAutoShowChangelog: changelog),
            .welcome,
            "Both gates say yes here. Exactly one window may open, and someone who still needs setup does not need release notes."
        )
    }

    func testChangelogStillShowsWhenTheTourIsNotWanted() {
        XCTAssertEqual(
            OnboardingFlow.launchPresentation(shouldPresentWelcome: false, shouldAutoShowChangelog: true),
            .changelog,
            "Suppressing the tour must not suppress What's New for an established user."
        )
        XCTAssertEqual(
            OnboardingFlow.launchPresentation(shouldPresentWelcome: false, shouldAutoShowChangelog: false),
            .none,
            "A configured, up-to-date launch opens nothing."
        )
    }

    // MARK: - Blocking vs recommended

    func testOnlyTheProviderStepBlocksRecording() {
        XCTAssertTrue(OnboardingStep.provider.blocksRecording)
        XCTAssertFalse(OnboardingStep.microphone.blocksRecording)
        XCTAssertFalse(
            OnboardingStep.hotkeys.blocksRecording,
            "Hotkeys are opt-in by the 1.0.11 decision; not assigning them must never block recording."
        )
    }

    func testBlockingIncompleteStepsNamesOnlyTheProvider() {
        XCTAssertEqual(OnboardingFlow.blockingIncompleteSteps(in: snapshot()), [.provider])

        let providerDone = snapshot(credential: true)
        XCTAssertTrue(
            OnboardingFlow.blockingIncompleteSteps(in: providerDone).isEmpty,
            "With a usable provider, skipping the rest leaves recording available."
        )
    }

    private func makeTempDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-OnboardingFlowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

}
