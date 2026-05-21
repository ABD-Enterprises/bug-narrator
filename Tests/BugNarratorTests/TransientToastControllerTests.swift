import XCTest
@testable import BugNarrator

@MainActor
final class TransientToastControllerTests: XCTestCase {
    func testShowToastPresentsToastImmediately() {
        let presentationState = AppPresentationState()
        let controller = TransientToastController(presentationState: presentationState)

        controller.showToast("Saved", style: .success)

        XCTAssertEqual(presentationState.transientToast?.message, "Saved")
        XCTAssertEqual(presentationState.transientToast?.style, .success)
    }

    func testShowToastReplacesActiveToastAndCancelsPriorDismissal() async {
        let presentationState = AppPresentationState()
        let controller = TransientToastController(presentationState: presentationState)

        controller.showToast("First", style: .success, durationNanoseconds: 5_000_000)
        controller.showToast("Second", style: .informational, durationNanoseconds: 1_000_000_000)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(presentationState.transientToast?.message, "Second")
        XCTAssertEqual(presentationState.transientToast?.style, .informational)
    }

    func testShowToastDismissesAfterDelay() async {
        let presentationState = AppPresentationState()
        let controller = TransientToastController(presentationState: presentationState)

        controller.showToast("Saved", durationNanoseconds: 5_000_000)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(presentationState.transientToast)
    }

    func testDismissToastCancelsScheduledDismissal() async {
        let presentationState = AppPresentationState()
        let controller = TransientToastController(presentationState: presentationState)

        controller.showToast("Saved", durationNanoseconds: 1_000_000_000)
        controller.dismissToast()
        try? await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertNil(presentationState.transientToast)
    }
}
