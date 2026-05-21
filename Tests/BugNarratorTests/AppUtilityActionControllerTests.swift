import XCTest
@testable import BugNarrator

@MainActor
final class AppUtilityActionControllerTests: XCTestCase {
    func testWindowActionsInvokeRegisteredCallbacks() {
        let harness = AppUtilityActionControllerHarness()
        var openedWindows: [String] = []
        harness.controller.showTranscriptWindow = { openedWindows.append("transcript") }
        harness.controller.showSettingsWindow = { openedWindows.append("settings") }
        harness.controller.showSupportWindow = { openedWindows.append("support") }
        harness.controller.showRecordingControlWindow = { openedWindows.append("recording") }

        harness.controller.openTranscriptHistory()
        harness.controller.openSettings()
        harness.controller.openSupportDevelopment()
        harness.controller.openRecordingControls()

        XCTAssertEqual(openedWindows, ["transcript", "settings", "support", "recording"])
    }

    func testExternalURLActionOpensExpectedLink() {
        let harness = AppUtilityActionControllerHarness()

        let result = harness.controller.openDocumentation()

        XCTAssertEqual(result, .opened)
        XCTAssertEqual(harness.urlHandler.openedURLs, [BugNarratorLinks.documentation])
    }

    func testExternalURLFailureReturnsFailureMessage() {
        let harness = AppUtilityActionControllerHarness()
        harness.urlHandler.shouldSucceed = false

        let result = harness.controller.openIssueReporter()

        XCTAssertEqual(result, .failed(message: "BugNarrator could not open the issue tracker."))
        XCTAssertEqual(harness.urlHandler.openedURLs, [BugNarratorLinks.issues])
    }

    func testPrivacySettingsActionDelegatesToPermissionRecoveryController() {
        let harness = AppUtilityActionControllerHarness()

        let result = harness.controller.openMicrophonePrivacySettings()

        XCTAssertEqual(result, .opened(BugNarratorLinks.microphonePrivacySettings))
        XCTAssertEqual(harness.urlHandler.openedURLs, [BugNarratorLinks.microphonePrivacySettings])
    }

    func testFailureStatusPreservesActiveWorkPhases() {
        let message = "BugNarrator could not open the documentation."

        XCTAssertEqual(
            AppUtilityActionResultPresenter.failureStatus(message: message, statusPhase: .recording),
            .recording("BugNarrator could not open the documentation. Recording is still active.")
        )
        XCTAssertEqual(
            AppUtilityActionResultPresenter.failureStatus(message: message, statusPhase: .transcribing),
            .transcribing("BugNarrator could not open the documentation. Background work is still in progress.")
        )
    }

    func testFailureStatusMapsInactivePhasesToError() {
        let message = "The selected screenshot file is no longer available on this Mac."

        XCTAssertEqual(
            AppUtilityActionResultPresenter.failureStatus(message: message, statusPhase: .idle),
            .error(message)
        )
        XCTAssertEqual(
            AppUtilityActionResultPresenter.failureStatus(message: message, statusPhase: .success),
            .error(message)
        )
        XCTAssertEqual(
            AppUtilityActionResultPresenter.failureStatus(message: message, statusPhase: .error),
            .error(message)
        )
    }

    func testPresenterAppliesFailedResultsAndIgnoresOpenedResults() {
        var phase = AppStatus.Phase.idle
        var statuses: [AppStatus] = []
        let presenter = AppUtilityActionResultPresenter(
            statusPhase: { phase },
            setStatus: { statuses.append($0) }
        )

        presenter.present(AppUtilityActionResult.opened)
        presenter.present(PermissionSettingsOpenResult.opened(BugNarratorLinks.microphonePrivacySettings))
        XCTAssertTrue(statuses.isEmpty)

        presenter.present(AppUtilityActionResult.failed(message: "BugNarrator could not open the issue tracker."))
        phase = .recording
        presenter.present(PermissionSettingsOpenResult.failed("BugNarrator could not open System Settings."))

        XCTAssertEqual(
            statuses,
            [
                .error("BugNarrator could not open the issue tracker."),
                .recording("BugNarrator could not open System Settings. Recording is still active.")
            ]
        )
    }
}

@MainActor
private final class AppUtilityActionControllerHarness {
    let urlHandler = MockURLHandler()
    let controller: AppUtilityActionController

    init() {
        let microphonePermissionService = MicrophonePermissionService(permissionAccess: MockAudioRecorder())
        let screenCapturePermissionService = ScreenCapturePermissionService(
            permissionAccess: MockScreenCapturePermissionAccess()
        )
        let permissionRecoveryController = PermissionRecoveryController(
            microphonePermissionService: microphonePermissionService,
            screenCapturePermissionService: screenCapturePermissionService,
            urlHandler: urlHandler,
            runtimeEnvironment: AppRuntimeEnvironment()
        )
        self.controller = AppUtilityActionController(
            urlHandler: urlHandler,
            permissionRecoveryController: permissionRecoveryController
        )
    }
}
