import XCTest
@testable import BugNarrator

final class TranscriptQualityFindingTests: XCTestCase {
    func testFindingIDCombinesKindSeverityAndMessage() {
        let finding = TranscriptQualityFinding(
            kind: .abruptEnding,
            severity: .warning,
            message: "Transcript appears to end mid-sentence."
        )

        XCTAssertEqual(finding.id, "abruptEnding-warning-Transcript appears to end mid-sentence.")
    }

    func testFindingCodableRoundTripPreservesSeverityAndKind() throws {
        let finding = TranscriptQualityFinding(
            kind: .unexpectedLanguageScript,
            severity: .error,
            message: "Unexpected script detected."
        )

        let data = try JSONEncoder().encode(finding)
        let decoded = try JSONDecoder().decode(TranscriptQualityFinding.self, from: data)

        XCTAssertEqual(decoded, finding)
    }
}
