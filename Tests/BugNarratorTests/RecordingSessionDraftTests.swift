import XCTest
@testable import BugNarrator

final class RecordingSessionDraftTests: XCTestCase {
    func testDraftPreservesRecordingArtifactsAndTimelineState() {
        let sessionID = UUID()
        let markerID = UUID()
        let screenshotID = UUID()
        let marker = SessionMarker(
            id: markerID,
            index: 1,
            elapsedTime: 12,
            createdAt: Date(timeIntervalSince1970: 100),
            title: "Checkout failed",
            note: "Clicked Pay.",
            screenshotID: screenshotID
        )
        let screenshot = SessionScreenshot(
            id: screenshotID,
            createdAt: Date(timeIntervalSince1970: 101),
            elapsedTime: 12,
            filePath: "/tmp/capture.png",
            associatedMarkerID: markerID
        )

        let draft = RecordingSessionDraft(
            sessionID: sessionID,
            artifactsDirectoryURL: URL(fileURLWithPath: "/tmp/session", isDirectory: true),
            markers: [marker],
            screenshots: [screenshot]
        )

        XCTAssertEqual(draft.sessionID, sessionID)
        XCTAssertEqual(draft.artifactsDirectoryURL.path, "/tmp/session")
        XCTAssertEqual(draft.markers, [marker])
        XCTAssertEqual(draft.screenshots, [screenshot])
    }
}
