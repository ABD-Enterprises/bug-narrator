import XCTest
@testable import BugNarrator

final class TransientToastTests: XCTestCase {
    func testToastDefaultsToSuccessStyle() {
        let toast = TransientToast(message: "Export complete.")

        XCTAssertEqual(toast.message, "Export complete.")
        XCTAssertEqual(toast.style, .success)
        XCTAssertEqual(toast.style.symbolName, "checkmark.circle.fill")
        XCTAssertFalse(toast.id.uuidString.isEmpty)
    }

    func testInformationalToastUsesDismissSymbol() {
        let toast = TransientToast(message: "Export dismissed.", style: .informational)

        XCTAssertEqual(toast.message, "Export dismissed.")
        XCTAssertEqual(toast.style, .informational)
        XCTAssertEqual(toast.style.symbolName, "xmark.circle")
    }
}
