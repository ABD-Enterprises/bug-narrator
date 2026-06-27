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
