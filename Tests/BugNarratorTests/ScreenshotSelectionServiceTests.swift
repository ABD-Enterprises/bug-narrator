import CoreGraphics
import XCTest
@testable import BugNarrator

final class ScreenshotSelectionServiceTests: XCTestCase {
    func testNormalizedSelectionRectReturnsStandardizedRect() {
        let rect = ScreenshotSelectionGeometry.normalizedSelectionRect(
            from: CGPoint(x: 80, y: 70),
            to: CGPoint(x: 20, y: 10)
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 10, width: 60, height: 60))
    }

    func testNormalizedSelectionRectReturnsNilForZeroSizedSelection() {
        let rect = ScreenshotSelectionGeometry.normalizedSelectionRect(
            from: CGPoint(x: 24, y: 24),
            to: CGPoint(x: 24, y: 24)
        )

        XCTAssertNil(rect)
    }

    func testNormalizedSelectionRectReturnsNilForTinySelection() {
        let rect = ScreenshotSelectionGeometry.normalizedSelectionRect(
            from: CGPoint(x: 10, y: 10),
            to: CGPoint(x: 12, y: 12)
        )

        XCTAssertNil(rect)
    }
}
