import XCTest
@testable import BugNarrator

final class TranscriptSectionTests: XCTestCase {
    func testSectionFormatsTimeRangeAndPreservesTimelineLinks() {
        let markerID = UUID()
        let screenshotIDs = [UUID(), UUID()]

        let section = TranscriptSection(
            id: UUID(),
            title: "Checkout flow",
            startTime: 61,
            endTime: 125,
            text: "Checkout became unresponsive after clicking Pay.",
            markerID: markerID,
            screenshotIDs: screenshotIDs
        )

        XCTAssertEqual(section.timeRangeLabel, "01:01 - 02:05")
        XCTAssertEqual(section.markerID, markerID)
        XCTAssertEqual(section.screenshotIDs, screenshotIDs)
    }

    func testSectionCodableRoundTripPreservesTextAndLinks() throws {
        let section = TranscriptSection(
            id: UUID(),
            title: "Login flow",
            startTime: 2,
            endTime: 9,
            text: "The login page did not show an error.",
            markerID: UUID(),
            screenshotIDs: [UUID()]
        )

        let data = try JSONEncoder().encode(section)
        let decoded = try JSONDecoder().decode(TranscriptSection.self, from: data)

        XCTAssertEqual(decoded, section)
    }
}
