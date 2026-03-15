import XCTest
@testable import BugNarrator

final class MicrophonePermissionResolverTests: XCTestCase {
    func testAuthorizedWinsWhenPermissionSourcesDisagree() {
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .authorized, audioPermission: .denied),
            .authorized
        )
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .denied, audioPermission: .authorized),
            .authorized
        )
    }

    func testNotDeterminedWinsOverDeniedWhenPermissionPromptIsStillPossible() {
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .notDetermined, audioPermission: .denied),
            .notDetermined
        )
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .denied, audioPermission: .notDetermined),
            .notDetermined
        )
    }

    func testRestrictedWinsWhenNothingIsAuthorizedOrRequestable() {
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .restricted, audioPermission: .denied),
            .restricted
        )
    }

    func testDeniedIsReturnedWhenBothSourcesAreDenied() {
        XCTAssertEqual(
            MicrophonePermissionResolver.resolve(capturePermission: .denied, audioPermission: .denied),
            .denied
        )
    }
}
