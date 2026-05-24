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

    func testNegativeDurationsClampToZero() {
        XCTAssertEqual(ElapsedTimeFormatter.string(from: -12), "00:00")
    }
}
