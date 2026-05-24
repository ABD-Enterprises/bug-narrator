import XCTest
@testable import BugNarrator

final class SessionScreenshotTests: XCTestCase {
    func testScreenshotDerivesFileURLFileNameAndTimeLabel() {
        let markerID = UUID()
        let screenshot = SessionScreenshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 25),
            elapsedTime: 3_661,
            filePath: "/tmp/BugNarrator/capture-001.png",
            associatedMarkerID: markerID
        )

        XCTAssertEqual(screenshot.fileURL.path, "/tmp/BugNarrator/capture-001.png")
        XCTAssertEqual(screenshot.fileName, "capture-001.png")
        XCTAssertEqual(screenshot.timeLabel, "1:01:01")
        XCTAssertEqual(screenshot.associatedMarkerID, markerID)
    }

    func testScreenshotCodableRoundTripPreservesAssociation() throws {
        let screenshot = SessionScreenshot(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 30),
            elapsedTime: 8,
            filePath: "/tmp/capture.png",
            associatedMarkerID: UUID()
        )

        let data = try JSONEncoder().encode(screenshot)
        let decoded = try JSONDecoder().decode(SessionScreenshot.self, from: data)

        XCTAssertEqual(decoded, screenshot)
    }
}
