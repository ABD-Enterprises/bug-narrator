import XCTest
@testable import BugNarrator

final class TranscriptQualityInspectorTests: XCTestCase {
    func testFindsRepeatedTextLoop() {
        let transcript = Array(repeating: "show you how it works", count: 6).joined(separator: " ")

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertEqual(findings.map(\.kind), [.repeatedText])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testFindsAbruptEndingForLongTranscript() {
        let transcript = """
        This customer call covered setup reliability, settings validation, tracker exports, transcript review,
        screenshot capture, issue extraction, and release readiness. The speaker was describing the final action that
        """

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .abruptEnding })
    }

    func testFindsEmptyTranscript() {
        let findings = TranscriptQualityInspector().findings(for: "   ")

        XCTAssertEqual(findings.map(\.kind), [.shortTranscript])
        XCTAssertEqual(findings.first?.severity, .error)
    }
}
