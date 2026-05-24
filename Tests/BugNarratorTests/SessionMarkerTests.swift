import XCTest
@testable import BugNarrator

final class SessionMarkerTests: XCTestCase {
    func testMarkerInitializesWithExplicitValuesAndFormattedTimeLabel() {
        let id = UUID()
        let screenshotID = UUID()
        let createdAt = Date(timeIntervalSince1970: 42)

        let marker = SessionMarker(
            id: id,
            index: 3,
            elapsedTime: 125,
            createdAt: createdAt,
            title: "Navigation stalled",
            note: "Spinner kept running.",
            screenshotID: screenshotID
        )

        XCTAssertEqual(marker.id, id)
        XCTAssertEqual(marker.index, 3)
        XCTAssertEqual(marker.createdAt, createdAt)
        XCTAssertEqual(marker.title, "Navigation stalled")
        XCTAssertEqual(marker.note, "Spinner kept running.")
        XCTAssertEqual(marker.screenshotID, screenshotID)
        XCTAssertEqual(marker.timeLabel, "02:05")
    }

    func testMarkerCodableRoundTripPreservesOptionalScreenshotReference() throws {
        let marker = SessionMarker(
            id: UUID(),
            index: 1,
            elapsedTime: 5,
            createdAt: Date(timeIntervalSince1970: 10),
            title: "Save failed",
            note: nil,
            screenshotID: UUID()
        )

        let data = try JSONEncoder().encode(marker)
        let decoded = try JSONDecoder().decode(SessionMarker.self, from: data)

        XCTAssertEqual(decoded, marker)
    }
}
