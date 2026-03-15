import XCTest
@testable import BugNarrator

@MainActor
final class ScreenCapturePermissionServiceTests: XCTestCase {
    func testCurrentStatusReturnsGrantedWhenPermissionIsAvailable() {
        let permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = .granted
        let service = ScreenCapturePermissionService(permissionAccess: permissionAccess)

        XCTAssertEqual(service.currentStatus(), .granted)
    }

    func testPreflightRequestsPermissionAndSucceedsWhenGranted() async {
        let permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = .notDetermined
        permissionAccess.requestedPermissionStates = [.granted]
        let screenshotService = MockScreenshotCaptureService()
        let service = ScreenCapturePermissionService(permissionAccess: permissionAccess)

        let result = await service.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotService,
            hasActiveRecordingSession: true
        )

        XCTAssertEqual(result, .success)
        XCTAssertEqual(permissionAccess.permissionRequestCallCount, 1)
    }

    func testPreflightReturnsNeedsUserActionWhenPermissionIsDenied() async {
        let permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = .denied
        let screenshotService = MockScreenshotCaptureService()
        let service = ScreenCapturePermissionService(permissionAccess: permissionAccess)

        let result = await service.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotService,
            hasActiveRecordingSession: true
        )

        XCTAssertEqual(result, .needsUserAction(.screenRecordingPermissionDenied))
    }

    func testPreflightReturnsFailureWhenCaptureValidationFailsAfterPermissionIsGranted() async {
        let permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = .granted
        let screenshotService = MockScreenshotCaptureService()
        screenshotService.availabilityError = .screenshotCaptureFailure("No displays were available to capture.")
        let service = ScreenCapturePermissionService(permissionAccess: permissionAccess)

        let result = await service.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotService,
            hasActiveRecordingSession: true
        )

        XCTAssertEqual(result, .failure(.screenshotCaptureFailure("No displays were available to capture.")))
    }

    func testPreflightReturnsBlockedWhenThereIsNoActiveRecordingSession() async {
        let permissionAccess = MockScreenCapturePermissionAccess()
        let screenshotService = MockScreenshotCaptureService()
        let service = ScreenCapturePermissionService(permissionAccess: permissionAccess)

        let result = await service.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotService,
            hasActiveRecordingSession: false
        )

        XCTAssertEqual(result, .blocked(.noActiveSession("Start a feedback session before capturing a screenshot.")))
    }
}
