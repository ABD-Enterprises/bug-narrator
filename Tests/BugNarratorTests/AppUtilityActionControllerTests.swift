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
