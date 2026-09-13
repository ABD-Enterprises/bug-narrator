import Foundation
import XCTest
@testable import BugNarrator

/// Characterization tests for the response parser extracted from
/// `IssueExtractionService` (#519). They pin the schema-repair / normalization
/// of a successful chat-completions body and the exact failure messages for
/// empty / refusal / unparseable responses. No network access.
final class IssueExtractionResponseParserTests: XCTestCase {
    private func session() -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "The save button is clipped.",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )
    }

    private func completionData(content: String) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: ["choices": [["message": ["content": content]]]]
        )
    }

    func testParsesSummaryGuidanceAndNormalizesIssuesIncludingAliasKeysAndFence() throws {
        let content = """
        ```json
        {
          "reviewSummary": "One draft issue was extracted.",
          "guidance_note": "Review before export.",
          "draftIssues": [
            {
              "issueTitle": "Save button clips in the modal",
              "type": "Bug",
              "severity": "High",
              "description": "The save button appears clipped in the modal layout.",
              "evidence": "The save button is clipped",
              "timecode": "00:08",
              "needsReview": true
            }
          ]
        }
        ```
        """

        let result = try IssueExtractionResponseParser.parseResult(
            from: try completionData(content: content),
            session: session()
        )

        XCTAssertEqual(result.summary, "One draft issue was extracted.")
        XCTAssertEqual(result.guidanceNote, "Review before export.")
        XCTAssertEqual(result.issues.count, 1)
        let issue = try XCTUnwrap(result.issues.first)
        XCTAssertEqual(issue.title, "Save button clips in the modal")
        XCTAssertEqual(issue.category, .bug)
        XCTAssertEqual(issue.severity, .high)
        XCTAssertEqual(issue.timestamp, 8)
        XCTAssertTrue(issue.requiresReview)
    }

    func testRefusalSurfacesRefusalTextVerbatim() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["choices": [["message": ["refusal": "I can't help with that."]]]]
        )
        XCTAssertThrowsError(try IssueExtractionResponseParser.parseResult(from: data, session: session())) { error in
            guard case AppError.issueExtractionFailure(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "I can't help with that.")
        }
    }

    func testEmptyContentReportsEmptyResponse() throws {
        let data = try completionData(content: "   ")
        XCTAssertThrowsError(try IssueExtractionResponseParser.parseResult(from: data, session: session())) { error in
            guard case AppError.issueExtractionFailure(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "The extraction response was empty.")
        }
    }

    func testUnparseableContentReportsUnexpectedFormat() throws {
        let data = try completionData(content: "this is not JSON at all")
        XCTAssertThrowsError(try IssueExtractionResponseParser.parseResult(from: data, session: session())) { error in
            guard case AppError.issueExtractionFailure(let message) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(
                message,
                "OpenAI returned issue data in an unexpected format. Try again, or switch the issue extraction model in Settings."
            )
        }
    }
}

// MARK: - non-finite numbers from the model (#1125)

/// `Double(String)` accepts "nan", "inf" and overflow, and `min(max(.nan, 0), 1)`
/// is NaN, so these used to reach `Int(...)` in confidenceLabel,
/// exportDescription and ElapsedTimeFormatter and trap. The parser is the one
/// place every model-sourced number passes through, so it rejects them there.
final class IssueExtractionResponseParserNonFiniteTests: XCTestCase {

    private func session() -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "The save button is clipped.",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [SessionScreenshot(elapsedTime: 4, filePath: "/tmp/shots/modal.png")]
        )
    }

    private func parse(issue: String) throws -> ExtractedIssue {
        let content = #"{"summary":"s","issues":[\#(issue)]}"#
        let data = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
        let result = try IssueExtractionResponseParser.parseResult(from: data, session: session())
        return try XCTUnwrap(result.issues.first)
    }

    private let base = #""title":"Clipped","category":"bug","summary":"s","evidenceExcerpt":"e""#

    func testNonFiniteIssueConfidenceBecomesNilAndTheLabelDoesNotTrap() throws {
        for value in ["nan", "NaN", "inf", "-inf", "1e309"] {
            let issue = try parse(issue: #"{\#(base),"confidence":"\#(value)"}"#)
            XCTAssertNil(issue.confidence, value)
            _ = issue.confidenceLabel
        }
        XCTAssertEqual(try parse(issue: #"{\#(base),"confidence":"0.5"}"#).confidence, 0.5)
    }

    func testBareNegativeOverflowLiteralIsRejectedToo() throws {
        // JSONSerialization rejects 1e999/NaN/Infinity but accepts -1e999 as -inf,
        // so the Double branch (not just the String branch) must guard.
        XCTAssertNil(try parse(issue: #"{\#(base),"confidence":-1e999}"#).confidence)
        let annotation = #"{"screenshot":"modal.png","label":"a","x":0.5,"y":0.5,"width":0.2,"height":0.2,"confidence":-1e999}"#
        XCTAssertNil(try parse(issue: #"{\#(base),"screenshotAnnotations":[\#(annotation)]}"#).screenshotAnnotations.first?.confidence)
    }

    func testNonFinitePrimaryKeyFallsThroughToTheAliasLikeAnyUnparseableValue() throws {
        // "nan" is treated exactly like "high": not a number, try the next key.
        XCTAssertEqual(try parse(issue: #"{\#(base),"confidence":"nan","score":0.7}"#).confidence, 0.7)
    }

    func testNonFiniteTimestampBecomesNilLikeAnAbsentOne() throws {
        // "1e308:00" has finite parts whose product overflows to inf.
        for value in ["nan:00", "00:inf", "1e309:00", "01:nan:00", "1e308:00", "1e307:1e308"] {
            let issue = try parse(issue: #"{\#(base),"timestamp":"\#(value)"}"#)
            XCTAssertNil(issue.timestamp, value)
        }
        XCTAssertEqual(try parse(issue: #"{\#(base),"timestamp":"01:05"}"#).timestamp, 65)
    }

    func testNonFiniteStepTimestampFallsBack() throws {
        let issue = try parse(issue: #"{\#(base),"timestamp":"00:10","reproductionSteps":[{"instruction":"Open","timestamp":"nan:00"}]}"#)
        XCTAssertEqual(issue.reproductionSteps.first?.timestamp, 10, "falls back to the issue timestamp")
    }

    func testAnnotationWithANonFiniteCoordinateIsDroppedAndSiblingsSurvive() throws {
        for (key, value) in [("x", "nan"), ("y", "inf"), ("width", "-inf"), ("height", "1e309")] {
            let bad = #"{"screenshot":"modal.png","label":"bad","x":0.1,"y":0.1,"width":0.2,"height":0.2}"#
                .replacingOccurrences(of: #""\#(key)":0.\#(key == "x" || key == "y" ? "1" : "2")"#, with: #""\#(key)":"\#(value)""#)
            let good = #"{"screenshot":"modal.png","label":"good","x":0.5,"y":0.5,"width":0.2,"height":0.2}"#
            let issue = try parse(issue: #"{\#(base),"screenshotAnnotations":[\#(bad),\#(good)]}"#)

            XCTAssertEqual(issue.screenshotAnnotations.map(\.label), ["good"], "\(key)=\(value)")
            for annotation in issue.screenshotAnnotations { _ = annotation.exportDescription }
        }
    }

    func testNonFiniteAnnotationConfidenceBecomesNil() throws {
        let annotation = #"{"screenshot":"modal.png","label":"a","x":0.5,"y":0.5,"width":0.2,"height":0.2,"confidence":"nan"}"#
        let issue = try parse(issue: #"{\#(base),"screenshotAnnotations":[\#(annotation)]}"#)
        XCTAssertEqual(issue.screenshotAnnotations.count, 1)
        XCTAssertNil(issue.screenshotAnnotations.first?.confidence)
        _ = issue.screenshotAnnotations.first?.confidenceLabel
    }
}
