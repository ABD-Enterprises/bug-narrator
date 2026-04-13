import Foundation
import XCTest
@testable import BugNarrator

final class IssueExtractionServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testExtractIssuesReturnsStructuredDraftIssues() async throws {
        let session = makeReviewSession()

        let content = """
        {
          "summary": "Two draft review items were extracted.",
          "guidanceNote": "Review these before export.",
          "issues": [
            {
              "title": "Save button clips in the modal",
              "category": "Bug",
              "severity": "High",
              "component": "Settings > Save Modal",
              "summary": "The save button appears clipped in the modal layout.",
              "evidenceExcerpt": "The save button is clipped",
              "deduplicationHint": "issue-save-modal-clipped",
              "timestamp": "00:08",
              "sectionTitle": "Save flow",
              "relatedScreenshotFileNames": ["review-shot.png"],
              "reproductionSteps": [
                {
                  "instruction": "Open the save modal.",
                  "expectedResult": "The primary action fits within the modal bounds.",
                  "actualResult": "The save button is clipped on the right edge.",
                  "timestamp": "00:08",
                  "relatedScreenshotFileName": "review-shot.png"
                }
              ],
              "confidence": 0.74,
              "requiresReview": true
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-openai-key")

            return (self.successResponse(for: request), self.makeChatCompletionData(content: content))
        }

        let service = IssueExtractionService(session: makeMockURLSession())
        let result = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")

        XCTAssertEqual(result.summary, "Two draft review items were extracted.")
        XCTAssertEqual(result.guidanceNote, "Review these before export.")
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.category, .bug)
        XCTAssertEqual(result.issues.first?.severity, .high)
        XCTAssertEqual(result.issues.first?.component, "Settings > Save Modal")
        XCTAssertEqual(result.issues.first?.relatedScreenshotIDs, [try XCTUnwrap(session.screenshots.first?.id)])
        XCTAssertEqual(result.issues.first?.deduplicationHint, "issue-save-modal-clipped")
        XCTAssertEqual(result.issues.first?.timestamp, 8)
        XCTAssertEqual(result.issues.first?.reproductionSteps.count, 1)
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.instruction, "Open the save modal.")
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.expectedResult, "The primary action fits within the modal bounds.")
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.actualResult, "The save button is clipped on the right edge.")
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.timestamp, 8)
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.screenshotID, session.screenshots.first?.id)
    }

    func testExtractIssuesParsesArrayBasedContentWithMarkdownFenceAndAliasKeys() async throws {
        let session = makeReviewSession()

        let fencedJSON = """
        ```json
        {
          "reviewSummary": "One draft issue was extracted.",
          "guidance_note": "Review before export.",
          "draftIssues": [
            {
              "issueTitle": "Save button clips in the modal",
              "type": "Bug",
              "description": "The save button appears clipped in the modal layout.",
              "evidence": "The save button is clipped",
              "timecode": "00:08",
              "section": "Save flow",
              "screenshotFileNames": ["review-shot.png"],
              "stepsToReproduce": [
                {
                  "step": "Open the save modal.",
                  "expected": "The save button is fully visible.",
                  "actual": "The save button clips against the modal frame."
                }
              ],
              "score": 0.74,
              "needsReview": true
            }
          ]
        }
        ```
        """

        MockURLProtocol.requestHandler = { request in
            (
                self.successResponse(for: request),
                try JSONSerialization.data(
                    withJSONObject: [
                        "choices": [
                            [
                                "message": [
                                    "content": [
                                        ["type": "text", "text": fencedJSON]
                                    ]
                                ]
                            ]
                        ]
                    ]
                )
            )
        }

        let service = IssueExtractionService(session: makeMockURLSession())
        let result = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")

        XCTAssertEqual(result.summary, "One draft issue was extracted.")
        XCTAssertEqual(result.guidanceNote, "Review before export.")
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertEqual(result.issues.first?.title, "Save button clips in the modal")
        XCTAssertEqual(result.issues.first?.category, .bug)
        XCTAssertEqual(result.issues.first?.severity, .medium)
        XCTAssertEqual(result.issues.first?.component, "Save flow")
        XCTAssertEqual(result.issues.first?.relatedScreenshotIDs, [session.screenshots.first?.id].compactMap { $0 })
        XCTAssertTrue(result.issues.first?.deduplicationHint.hasPrefix("issue-") == true)
        XCTAssertEqual(result.issues.first?.timestamp, 8)
        XCTAssertEqual(result.issues.first?.reproductionSteps.count, 1)
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.timestamp, 8)
        XCTAssertEqual(result.issues.first?.reproductionSteps.first?.screenshotID, session.screenshots.first?.id)
    }

    func testExtractIssuesInfersSeverityAndDeduplicationHintWhenMissing() async throws {
        let session = makeReviewSession()
        let content = """
        {
          "summary": "One draft issue was extracted.",
          "issues": [
            {
              "title": "Submit button does not respond",
              "category": "Bug",
              "summary": "The submit button does not respond after entering valid input.",
              "evidenceExcerpt": "This is completely broken because the submit button never responds.",
              "timestamp": "00:08"
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            (self.successResponse(for: request), self.makeChatCompletionData(content: content))
        }

        let service = IssueExtractionService(session: makeMockURLSession())
        let result = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")

        XCTAssertEqual(result.issues.first?.severity, .critical)
        XCTAssertTrue(result.issues.first?.deduplicationHint.hasPrefix("issue-") == true)
    }

    func testExtractIssuesReturnsClearErrorForMalformedStructuredPayload() async throws {
        let session = makeReviewSession()
        let malformedContent = """
        {
          "summary": "One draft issue was extracted.",
          "issues": [
            {
              "category": "Bug"
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            (self.successResponse(for: request), self.makeChatCompletionData(content: malformedContent))
        }

        let service = IssueExtractionService(session: makeMockURLSession())
        do {
            _ = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")
            XCTFail("Expected issue extraction to fail for malformed payload.")
        } catch {
            XCTAssertEqual(
                error as? AppError,
                .issueExtractionFailure("OpenAI returned issue data in an unexpected format. Try again, or switch the issue extraction model in Settings.")
            )
        }
    }

    func testExtractIssuesTimesOutAfterConfiguredBudget() async throws {
        let session = makeReviewSession()

        MockURLProtocol.requestHandler = { request in
            Thread.sleep(forTimeInterval: 0.3)
            return (self.successResponse(for: request), self.makeChatCompletionData(content: #"{"summary":"","guidanceNote":"","issues":[]}"#))
        }

        let service = IssueExtractionService(
            session: makeMockURLSession(),
            timeoutDuration: .milliseconds(250)
        )

        do {
            _ = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")
            XCTFail("Expected issue extraction to time out.")
        } catch {
            XCTAssertEqual(
                error as? AppError,
                .issueExtractionFailure(
                    "Issue extraction took longer than 0.3 seconds. Retry the extraction or choose a faster model in Settings."
                )
            )
        }
    }

    private func makeReviewSession() -> TranscriptSession {
        let screenshot = SessionScreenshot(elapsedTime: 8, filePath: "/tmp/review-shot.png")
        return TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "The save button is clipped and the modal is confusing.",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [SessionMarker(index: 1, elapsedTime: 8, title: "Save flow", screenshotID: screenshot.id)],
            screenshots: [screenshot],
            sections: [
                TranscriptSection(
                    title: "Save flow",
                    startTime: 0,
                    endTime: 18,
                    text: "The save button is clipped and the modal is confusing.",
                    markerID: nil,
                    screenshotIDs: [screenshot.id]
                )
            ]
        )
    }

    private func successResponse(for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: try! XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    private func makeChatCompletionData(content: String) -> Data {
        try! JSONSerialization.data(
            withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": content
                        ]
                    ]
                ]
            ]
        )
    }
}
