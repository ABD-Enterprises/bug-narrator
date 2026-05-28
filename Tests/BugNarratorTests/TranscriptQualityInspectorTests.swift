import XCTest
@testable import BugNarrator

final class TranscriptQualityInspectorTests: XCTestCase {
    func testFindsRepeatedTextLoop() {
        let transcript = Array(repeating: "show you how it works", count: 4).joined(separator: " ")

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertEqual(findings.map(\.kind), [.repeatedText])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testFindsAdjacentShortRepeatedTextLoop() {
        let transcript = """
        The tester clicked refresh and the app crashed. please wait please wait please wait please wait before moving on.
        """

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .repeatedText })
    }

    func testFindsSingleWordRepeatedTextLoop() {
        let transcript = "The recorder returned you you you you you you after the tester stopped talking."

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .repeatedText })
    }

    func testFindsLikelyBoilerplateHallucination() {
        let transcript = "Thanks for watching. Please subscribe."

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .boilerplateText })
    }

    func testFindsLowInformationBoilerplateTranscript() {
        let transcript = "This is the end of the"

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .boilerplateText })
    }

    func testDoesNotFlagNormalShortNarrationAsBoilerplate() {
        let transcript = "Clicked refresh and the command center crashed."

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertFalse(findings.contains { $0.kind == .boilerplateText })
    }

    func testFindsUnexpectedCJKScriptForLikelyEnglishTranscript() {
        let transcript = """
        The tester opened the command center and clicked refresh. 然后 the expected setup panel did not appear.
        """

        let findings = TranscriptQualityInspector().findings(for: transcript)

        XCTAssertTrue(findings.contains { $0.kind == .unexpectedLanguageScript })
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
