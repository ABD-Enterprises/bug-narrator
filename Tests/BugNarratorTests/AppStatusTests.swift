import XCTest
@testable import BugNarrator

final class AppStatusTests: XCTestCase {
    func testStatusesExposePhaseTitleAndDetail() {
        let cases: [(status: AppStatus, phase: AppStatus.Phase, title: String, detail: String?)] = [
            (.idle(), .idle, "Idle", nil),
            (.idle("Ready"), .idle, "Idle", "Ready"),
            (.recording("00:05"), .recording, "Recording", "00:05"),
            (.transcribing("Uploading"), .transcribing, "Transcribing", "Uploading"),
            (.success("Saved"), .success, "Success", "Saved"),
            (.error("Failed"), .error, "Error", "Failed")
        ]

        for testCase in cases {
            XCTAssertEqual(testCase.status.phase, testCase.phase)
            XCTAssertEqual(testCase.status.title, testCase.title)
            XCTAssertEqual(testCase.status.detail, testCase.detail)
        }
    }
}
