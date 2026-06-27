import Foundation
import XCTest
@testable import BugNarrator

/// Characterization tests pinning the OpenAI issue-extraction request shape after
/// it was split out of `IssueExtractionService` into `IssueExtractionRequestBuilder`
/// (#432). These assert the request is byte-compatible with the prior in-service
/// implementation: the exact system prompt, the user-prompt assembly, and the
/// HTTP envelope. No network access.
final class IssueExtractionRequestBuilderTests: XCTestCase {
    private static let pinnedSystemPrompt = """
    You convert spoken software review notes into structured, reviewable draft issues.
    Use only information explicitly present in the transcript, markers, and screenshot references.
    Return strict JSON with keys summary, guidanceNote, issues.
    Each issue must contain title, category, severity, component, summary, evidenceExcerpt, deduplicationHint, timestamp, sectionTitle, relatedScreenshotFileNames, confidence, requiresReview, reproductionSteps, screenshotAnnotations.
    Each reproduction step must contain instruction, expectedResult, actualResult, timestamp, relatedScreenshotFileName.
    Each screenshot annotation must contain relatedScreenshotFileName, label, x, y, width, height, confidence, style.
    Generate numbered reproduction steps that follow the narration timeline and tie each step to the most relevant screenshot reference when one exists.
    When the narration clearly points to a specific UI control or region, return one or more screenshotAnnotations that use normalized 0-1 coordinates relative to the screenshot image.
    Use a top-left origin for x and y.
    Only include screenshotAnnotations when the narration or evidence clearly references a specific UI element. Otherwise return an empty array.
    Valid annotation styles are exactly: highlight.
    Valid categories are exactly: Bug, UX Issue, Enhancement, Question / Follow-up.
    Valid severities are exactly: Critical, High, Medium, Low.
    Infer severity from the narration tone and impact. Infer component from the most specific app area available in the transcript or screenshot context.
    DeduplicationHint should be a short stable hash-like string derived from the issue description.
    Prefer conservative output. If evidence is weak, set requiresReview to true and use a lower confidence.
    """

    func testMakeRequestBuildsHTTPEnvelopeAndModelParameters() throws {
        let session = Self.makeDeterministicSession()
        let request = try IssueExtractionRequestBuilder.makeRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            reviewSession: session,
            apiKey: "fixture-openai-key",
            model: "gpt-4.1-mini"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-openai-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let payload = try Self.decodeBody(request)
        XCTAssertEqual(payload["model"] as? String, "gpt-4.1-mini")
        XCTAssertEqual(payload["temperature"] as? Double, 0.1)
        let responseFormat = try XCTUnwrap(payload["response_format"] as? [String: Any])
        XCTAssertEqual(responseFormat["type"] as? String, "json_object")
    }

    func testMakeRequestOmitsAuthorizationHeaderForEmptyAPIKey() throws {
        let request = try IssueExtractionRequestBuilder.makeRequest(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            reviewSession: Self.makeDeterministicSession(),
            apiKey: "   ",
            model: "llama3.1:8b"
        )
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testSystemPromptIsPinnedVerbatim() throws {
        let request = try IssueExtractionRequestBuilder.makeRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            reviewSession: Self.makeDeterministicSession(),
            apiKey: "fixture-openai-key",
            model: "gpt-4.1-mini"
        )

        let messages = try Self.messages(request)
        let systemMessage = try XCTUnwrap(messages.first)
        XCTAssertEqual(systemMessage["role"] as? String, "system")
        XCTAssertEqual(systemMessage["content"] as? String, Self.pinnedSystemPrompt)
    }

    func testUserPromptAssemblyIsPinned() throws {
        let session = Self.makeDeterministicSession()
        let request = try IssueExtractionRequestBuilder.makeRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            reviewSession: session,
            apiKey: "fixture-openai-key",
            model: "gpt-4.1-mini"
        )

        let messages = try Self.messages(request)
        XCTAssertEqual(messages.count, 2)
        let userMessage = try XCTUnwrap(messages.last)
        XCTAssertEqual(userMessage["role"] as? String, "user")

        // With no screenshots there is exactly one user content part: the prompt.
        let parts = try XCTUnwrap(userMessage["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?["type"] as? String, "text")
        let promptText = try XCTUnwrap(parts.first?["text"] as? String)

        let marker = try XCTUnwrap(session.markers.first)
        let sectionLine = "## \(session.sections[0].title) [\(session.sections[0].timeRangeLabel)]"
        let expected: [String] = [
            "Session metadata:",
            // "- Recorded: ..." is locale/timezone-dependent; asserted separately.
            "- Duration: \(ElapsedTimeFormatter.string(from: session.duration))",
            "- Transcript model: \(session.model)",
            "",
            "Markers:",
            "- \(marker.title) at \(marker.timeLabel)",
            "",
            "Screenshots:",
            "- None",
            "",
            "Transcript sections:",
            sectionLine,
            session.sections[0].text,
            "",
            "Return a concise summary plus reviewable draft issues for product and engineering triage."
        ]

        var lines = promptText.components(separatedBy: "\n")
        XCTAssertEqual(lines.first, "Session metadata:")
        // Pull out and verify the dynamic Recorded line, then compare the rest.
        XCTAssertTrue(lines.count > 1)
        let recordedLine = lines.remove(at: 1)
        XCTAssertTrue(recordedLine.hasPrefix("- Recorded: "), recordedLine)
        XCTAssertEqual(lines, expected)
    }

    func testScreenshotContentPartsAndBudgetNoteArePinned() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-RequestBuilderScreenshot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pngData = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
        )!
        let screenshotURL = directory.appendingPathComponent("review-shot.png")
        try pngData.write(to: screenshotURL)
        let screenshot = SessionScreenshot(elapsedTime: 8, filePath: screenshotURL.path)
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "The save button is clipped.",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [],
            screenshots: [screenshot],
            sections: [
                TranscriptSection(
                    title: "Save flow",
                    startTime: 0,
                    endTime: 18,
                    text: "The save button is clipped.",
                    markerID: nil,
                    screenshotIDs: [screenshot.id]
                )
            ]
        )

        let request = try IssueExtractionRequestBuilder.makeRequest(
            endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
            reviewSession: session,
            apiKey: "fixture-openai-key",
            model: "gpt-4.1-mini"
        )

        let parts = try XCTUnwrap(try Self.messages(request).last?["content"] as? [[String: Any]])
        // Expected order: prompt text, screenshot reference text, image part, budget note.
        XCTAssertEqual(parts.count, 4)

        XCTAssertEqual(parts[0]["type"] as? String, "text")
        XCTAssertEqual(
            parts[1]["type"] as? String,
            "text"
        )
        XCTAssertEqual(
            parts[1]["text"] as? String,
            "Screenshot reference: \(screenshot.fileName) at \(screenshot.timeLabel)."
        )

        XCTAssertEqual(parts[2]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(parts[2]["image_url"] as? [String: Any])
        XCTAssertEqual(
            imageURL["url"] as? String,
            "data:image/png;base64,\(pngData.base64EncodedString())"
        )

        XCTAssertEqual(parts[3]["type"] as? String, "text")
        XCTAssertEqual(
            parts[3]["text"] as? String,
            "Screenshot budget note: included 1 screenshot(s), \(pngData.count) total bytes."
        )
    }

    // MARK: - Fixtures

    private static func makeDeterministicSession() -> TranscriptSession {
        // No screenshots → no file IO, no image parts, no budget notes: the user
        // content is exactly the prompt text, making the assembly deterministic.
        TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 10),
            transcript: "The save button is clipped and the modal is confusing.",
            duration: 18,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [SessionMarker(index: 1, elapsedTime: 8, title: "Save flow", screenshotID: nil)],
            screenshots: [],
            sections: [
                TranscriptSection(
                    title: "Save flow",
                    startTime: 0,
                    endTime: 18,
                    text: "The save button is clipped and the modal is confusing.",
                    markerID: nil,
                    screenshotIDs: []
                )
            ]
        )
    }

    private static func decodeBody(_ request: URLRequest) throws -> [String: Any] {
        let body = try requestBodyData(from: request)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private static func messages(_ request: URLRequest) throws -> [[String: Any]] {
        try XCTUnwrap(try decodeBody(request)["messages"] as? [[String: Any]])
    }
}
