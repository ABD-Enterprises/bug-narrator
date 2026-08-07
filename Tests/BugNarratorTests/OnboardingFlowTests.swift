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
            OnboardingFlow.shouldPresentOnLaunch(hasCompletedFirstRunOnboarding: false, snapshot: fresh)
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
            OnboardingFlow.shouldPresentOnLaunch(hasCompletedFirstRunOnboarding: false, snapshot: done)
        )
    }

    // MARK: - Skipped

    func testSkippingSuppressesTheFlowOnLaterLaunches() {
        let stillUnconfigured = snapshot()

        XCTAssertFalse(
            OnboardingFlow.shouldPresentOnLaunch(hasCompletedFirstRunOnboarding: true, snapshot: stillUnconfigured),
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
}
