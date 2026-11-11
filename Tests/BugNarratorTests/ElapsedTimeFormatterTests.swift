import XCTest
@testable import BugNarrator

final class ElapsedTimeFormatterTests: XCTestCase {
    func testFormatsSubHourDurationsAsMinutesAndSeconds() {
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 0), "00:00")
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 9.4), "00:09")
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 59.5), "01:00")
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 90.4), "01:30")
    }

    func testFormatsHourDurationsWithPaddedMinutesAndSeconds() {
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 3_600), "1:00:00")
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 3_661.2), "1:01:01")
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 7_325), "2:02:05")
    }

    func testUnrepresentableDurationsCannotTrapIntegerConversion() {
        for value in [Double.nan, .infinity, -.infinity, 1e308, -1e308, Double(Int.max)] {
            XCTAssertEqual(ElapsedTimeFormatter.string(from: value), "00:00")
        }
        XCTAssertEqual(ElapsedTimeFormatter.string(from: 1e15), "277777777777:46:40")
        XCTAssertFalse(ElapsedTimeFormatter.string(from: Double(Int.max).nextDown).isEmpty)
    }

    func testNegativeDurationsClampToZero() {
        XCTAssertEqual(ElapsedTimeFormatter.string(from: -12), "00:00")
    }
}
