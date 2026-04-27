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
              "screenshotAnnotations": [
                {
                  "relatedScreenshotFileName": "review-shot.png",
                  "label": "Save button",
                  "x": 0.48,
                  "y": 0.62,
                  "width": 0.22,
                  "height": 0.14,
                  "confidence": 0.81,
                  "style": "highlight"
                }
              ],
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

            let body = try requestBodyData(from: request)
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
            let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            XCTAssertTrue(userContent.contains(where: { ($0["type"] as? String) == "image_url" }))

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
        XCTAssertEqual(result.issues.first?.screenshotAnnotations.count, 1)
        XCTAssertEqual(result.issues.first?.screenshotAnnotations.first?.label, "Save button")
        XCTAssertEqual(result.issues.first?.screenshotAnnotations.first?.screenshotID, session.screenshots.first?.id)
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
              "annotations": [
                {
                  "screenshot": "review-shot.png",
                  "target": "Save button",
                  "left": 0.45,
                  "top": 0.60,
                  "w": 0.24,
                  "h": 0.15
                }
              ],
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
        XCTAssertEqual(result.issues.first?.screenshotAnnotations.count, 1)
        XCTAssertEqual(result.issues.first?.screenshotAnnotations.first?.label, "Save button")
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

    func testDeduplicationHintUsesFixedLocaleNormalization() {
        let title = "ISTANBUL ISSUE"
        let summary = "I expected the icon to stay visible."
        let evidenceExcerpt = "The icon disappears immediately."

        let hint = ExtractedIssue.makeDeduplicationHint(
            title: title,
            summary: summary,
            evidenceExcerpt: evidenceExcerpt
        )

        let posixHash = makeExpectedDeduplicationHint(
            title: title,
            summary: summary,
            evidenceExcerpt: evidenceExcerpt,
            locale: Locale(identifier: "en_US_POSIX")
        )
        let turkishHash = makeExpectedDeduplicationHint(
            title: title,
            summary: summary,
            evidenceExcerpt: evidenceExcerpt,
            locale: Locale(identifier: "tr_TR")
        )

        XCTAssertEqual(hint, posixHash)
        XCTAssertNotEqual(posixHash, turkishHash)
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

    func testExtractIssuesBudgetsTranscriptAndScreenshotPayload() async throws {
        let session = makeBudgetedReviewSession()
        defer {
            if let directoryURL = session.screenshots.first?.fileURL.deletingLastPathComponent() {
                try? FileManager.default.removeItem(at: directoryURL)
            }
        }

        MockURLProtocol.requestHandler = { request in
            let body = try requestBodyData(from: request)
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
            let userContent = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
            let textContent = userContent
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")

            XCTAssertEqual(userContent.filter { ($0["type"] as? String) == "image_url" }.count, 4)
            XCTAssertTrue(textContent.contains("Screenshot budget note: 2 screenshot(s) were omitted"))
            XCTAssertTrue(textContent.contains("Budget note: omitted"))
            XCTAssertFalse(textContent.contains("FINAL_SENTINEL_SHOULD_BE_OMITTED"))

            return (
                self.successResponse(for: request),
                self.makeChatCompletionData(content: #"{"summary":"Budgeted.","guidanceNote":"","issues":[]}"#)
            )
        }

        let service = IssueExtractionService(session: makeMockURLSession())
        let result = try await service.extractIssues(from: session, apiKey: "fixture-openai-key", model: "gpt-4.1-mini")

        XCTAssertEqual(result.summary, "Budgeted.")
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

    func testSimilarIssueReviewReturnsConfidenceRankedMatches() async throws {
        let session = makeReviewSession()
        let issue = ExtractedIssue(
            title: "Save button clips in the modal",
            category: .bug,
            summary: "The save button appears clipped in the modal layout.",
            evidenceExcerpt: "The save button is clipped",
            timestamp: 8,
            requiresReview: true,
            isSelectedForExport: true
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            let content = """
            {
              "matches": [
                {
                  "remoteIdentifier": "#142",
                  "confidence": 0.85,
                  "reasoning": "Both reports describe the same clipped primary action inside the save modal."
                }
              ]
            }
            """
            return (self.successResponse(for: request), self.makeChatCompletionData(content: content))
        }

        let service = SimilarIssueReviewService(session: makeMockURLSession())
        let review = try await service.prepareReview(
            issues: [issue],
            session: session,
            destination: .github,
            apiKey: "fixture-openai-key",
            model: "gpt-4.1-mini"
        ) { _ in
            [
                TrackerIssueCandidate(
                    remoteIdentifier: "#142",
                    title: "Save modal primary action is clipped",
                    summary: "The primary button clips against the modal edge.",
                    remoteURL: URL(string: "https://github.com/acme/bugnarrator/issues/142")
                )
            ]
        }

        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.items.first?.matches.first?.remoteIdentifier, "#142")
        XCTAssertEqual(review.items.first?.matches.first?.confidenceLabel, "85%")
        XCTAssertEqual(
            review.items.first?.matches.first?.reasoning,
            "Both reports describe the same clipped primary action inside the save modal."
        )
    }

    private func makeReviewSession() -> TranscriptSession {
        let screenshotURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("review-shot.png")
        let pngData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
        )!
        try? pngData.write(to: screenshotURL)
        let screenshot = SessionScreenshot(elapsedTime: 8, filePath: screenshotURL.path)
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

    private func makeBudgetedReviewSession() -> TranscriptSession {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-IssueExtractionBudget-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let pngData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
        )!
        let screenshots = (0..<6).map { index in
            let screenshotURL = directoryURL.appendingPathComponent("review-shot-\(index).png")
            try? pngData.write(to: screenshotURL)
            return SessionScreenshot(elapsedTime: TimeInterval(index), filePath: screenshotURL.path)
        }
        let longTranscript = String(
            repeating: "This transcript sentence should stay within the request budget while preserving useful issue context. ",
            count: 450
        ) + "FINAL_SENTINEL_SHOULD_BE_OMITTED"

        return TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 20),
            transcript: longTranscript,
            duration: 180,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: screenshots,
            sections: [
                TranscriptSection(
                    title: "Long review",
                    startTime: 0,
                    endTime: 180,
                    text: longTranscript,
                    markerID: nil,
                    screenshotIDs: screenshots.map(\.id)
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

    private func makeExpectedDeduplicationHint(
        title: String,
        summary: String,
        evidenceExcerpt: String,
        locale: Locale
    ) -> String {
        let normalized = [
            title,
            summary,
            evidenceExcerpt
        ]
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
        .lowercased(with: locale)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return String(format: "issue-%016llx", hash)
    }
}
