import XCTest
@testable import BugNarrator

@MainActor
final class PermissionRecoveryControllerTests: XCTestCase {
    func testStatusPresenterAppliesRecoveredStatus() {
        let harness = makeStatusPresenter(currentError: .microphonePermissionDenied)

        harness.presenter.present(.recovered(.idle("Microphone access enabled. You can start recording again.")))

        XCTAssertEqual(harness.presentationState.status, .idle("Microphone access enabled. You can start recording again."))
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testStatusPresenterLeavesUnchangedOutcomeUntouched() {
        let harness = makeStatusPresenter(
            status: .error("Microphone access is still blocked."),
            currentError: .microphonePermissionDenied
        )

        harness.presenter.present(.unchanged)

        XCTAssertEqual(harness.presentationState.status, .error("Microphone access is still blocked."))
        XCTAssertEqual(harness.presentationState.currentError, .microphonePermissionDenied)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testRefreshRecoversMicrophoneDeniedStateWhenAccessIsGranted() {
        let harness = PermissionRecoveryControllerHarness(microphonePermissionState: .authorized)

        let outcome = harness.controller.refreshRecoveryState(
            currentError: .microphonePermissionDenied,
            statusPhase: .idle
        )

        XCTAssertEqual(
            outcome,
            .recovered(.idle("Microphone access enabled. You can start recording again."))
        )
    }

    func testRefreshLeavesMicrophoneErrorWhenAccessIsStillBlocked() {
        let harness = PermissionRecoveryControllerHarness(microphonePermissionState: .denied)

        let outcome = harness.controller.refreshRecoveryState(
            currentError: .microphonePermissionDenied,
            statusPhase: .idle
        )

        XCTAssertEqual(outcome, .unchanged)
    }

    func testRefreshDoesNotClearMicrophoneErrorDuringRecording() {
        let harness = PermissionRecoveryControllerHarness(microphonePermissionState: .authorized)

        let outcome = harness.controller.refreshRecoveryState(
            currentError: .microphonePermissionDenied,
            statusPhase: .recording
        )

        XCTAssertEqual(outcome, .unchanged)
    }

    func testRefreshRecoversScreenRecordingStateWhileRecording() {
        let harness = PermissionRecoveryControllerHarness(screenPermissionState: .granted)

        let outcome = harness.controller.refreshRecoveryState(
            currentError: .screenRecordingPermissionDenied,
            statusPhase: .recording
        )

        XCTAssertEqual(
            outcome,
            .recovered(.recording("Screen Recording access enabled. You can capture screenshots again."))
        )
    }

    func testLocalTestingBuildAddsMicrophoneGuidanceNote() {
        let harness = PermissionRecoveryControllerHarness(
            microphonePermissionState: .denied,
            runtimeEnvironment: AppRuntimeEnvironment(
                bundlePath: "/tmp/DerivedData/BugNarrator/Build/Products/Debug/BugNarrator.app"
            )
        )

        let guidance = harness.controller.microphoneRecoveryGuidance(
            currentError: .microphonePermissionDenied
        )

        XCTAssertTrue(guidance.message.contains("System Settings > Privacy & Security > Microphone"))
        XCTAssertEqual(
            guidance.localTestingNote,
            "Local unsigned builds can need microphone approval again if you switch to a different app copy or rebuild into a new path. If System Settings already shows BugNarrator enabled, quit any other BugNarrator copies and retest the same app bundle path or the signed DMG build."
        )
    }

    func testOpenMicrophoneSettingsFallsBackToSecuritySettings() {
        let harness = PermissionRecoveryControllerHarness()
        harness.urlHandler.openResults = [false, true]

        let result = harness.controller.openMicrophonePrivacySettings()

        XCTAssertEqual(result, .opened(BugNarratorLinks.securityPrivacySettings))
        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [
                BugNarratorLinks.microphonePrivacySettings,
                BugNarratorLinks.securityPrivacySettings
            ]
        )
    }

    func testOpenSystemAudioSettingsReturnsFailureAfterAllCandidatesFail() {
        let harness = PermissionRecoveryControllerHarness()
        harness.urlHandler.shouldSucceed = false

        let result = harness.controller.openSystemAudioPrivacySettings()

        XCTAssertEqual(
            result,
            .failed("BugNarrator could not open Screen & System Audio Recording settings automatically.")
        )
        XCTAssertEqual(
            harness.urlHandler.openedURLs,
            [
                BugNarratorLinks.screenRecordingPrivacySettings,
                BugNarratorLinks.securityPrivacySettings,
                BugNarratorLinks.systemSettingsApp
            ]
        )
    }

    private func makeStatusPresenter(
        status: AppStatus = .idle(),
        currentError: AppError? = nil
    ) -> (
        presenter: PermissionRecoveryStatusPresenter,
        presentationState: AppPresentationState,
        telemetryRecorder: MockOperationalTelemetryRecorder
    ) {
        let presentationState = AppPresentationState(status: status, currentError: currentError)
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let presenter = PermissionRecoveryStatusPresenter(
            errorPresenter: AppErrorPresenter(
                presentationState: presentationState,
                telemetryRecorder: telemetryRecorder
            )
        )

        return (
            presenter: presenter,
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
    }
}

@MainActor
private final class PermissionRecoveryControllerHarness {
    let audioRecorder: MockAudioRecorder
    let screenCapturePermissionAccess: MockScreenCapturePermissionAccess
    let urlHandler: MockURLHandler
    let controller: PermissionRecoveryController

    init(
        microphonePermissionState: MicrophonePermissionState = .authorized,
        screenPermissionState: ScreenCapturePermissionState = .granted,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment(bundlePath: "/Applications/BugNarrator.app")
    ) {
        let audioRecorder = MockAudioRecorder()
        audioRecorder.permissionState = microphonePermissionState

        let screenCapturePermissionAccess = MockScreenCapturePermissionAccess()
        screenCapturePermissionAccess.permissionState = screenPermissionState

        let urlHandler = MockURLHandler()

        self.audioRecorder = audioRecorder
        self.screenCapturePermissionAccess = screenCapturePermissionAccess
        self.urlHandler = urlHandler
        self.controller = PermissionRecoveryController(
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            screenCapturePermissionService: ScreenCapturePermissionService(permissionAccess: screenCapturePermissionAccess),
            urlHandler: urlHandler,
            runtimeEnvironment: runtimeEnvironment
        )
    }
}
