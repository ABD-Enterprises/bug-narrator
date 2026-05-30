import Foundation
import XCTest
@testable import BugNarrator

final class ScreenshotAnnotationTests: XCTestCase {
    func testIssueScreenshotAnnotationMoveClampsIntoImageBounds() {
        var annotation = IssueScreenshotAnnotation(
            screenshotID: UUID(),
            label: "Primary button",
            x: 0.72,
            y: 0.68,
            width: 0.24,
            height: 0.18
        )

        annotation.move(x: 0.3, y: 0.3)

        XCTAssertEqual(annotation.x, 0.76, accuracy: 0.0001)
        XCTAssertEqual(annotation.y, 0.82, accuracy: 0.0001)
        XCTAssertEqual(annotation.width, 0.24, accuracy: 0.0001)
        XCTAssertEqual(annotation.height, 0.18, accuracy: 0.0001)
    }

    func testRendererWritesAnnotatedScreenshotAsset() throws {
        let screenshotURL = makeScreenshotFileURL(named: "annotation-source.png")
        let screenshot = SessionScreenshot(elapsedTime: 9, filePath: screenshotURL.path)
        let issue = ExtractedIssue(
            title: "Submit button does not respond",
            category: .bug,
            summary: "The highlighted submit button does not respond.",
            evidenceExcerpt: "The submit button never reacts to clicks.",
            timestamp: 9,
            relatedScreenshotIDs: [screenshot.id],
            screenshotAnnotations: [
                IssueScreenshotAnnotation(
                    screenshotID: screenshot.id,
                    label: "Submit button",
                    x: 0.42,
                    y: 0.56,
                    width: 0.22,
                    height: 0.16
                )
            ]
        )
        let outputDirectory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renderer = IssueScreenshotAnnotationRenderer()

        let asset = try renderer.writeAnnotatedScreenshot(
            for: issue,
            screenshot: screenshot,
            to: outputDirectory
        )

        XCTAssertNotNil(asset)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset?.fileURL.path ?? ""))
        XCTAssertTrue(asset?.fileName.contains("annotated") == true)
    }

    func testAnnotatedScreenshotExportsGathersOnlyAnnotatedScreenshots() throws {
        let annotatedURL = makeScreenshotFileURL(named: "exports-annotated.png")
        let annotatedScreenshot = SessionScreenshot(elapsedTime: 12, filePath: annotatedURL.path)
        let plainURL = makeScreenshotFileURL(named: "exports-plain.png")
        let plainScreenshot = SessionScreenshot(elapsedTime: 20, filePath: plainURL.path)
        let issue = ExtractedIssue(
            title: "Submit button does not respond",
            category: .bug,
            summary: "The highlighted submit button does not respond.",
            evidenceExcerpt: "The submit button never reacts to clicks.",
            timestamp: 12,
            relatedScreenshotIDs: [annotatedScreenshot.id, plainScreenshot.id],
            screenshotAnnotations: [
                IssueScreenshotAnnotation(
                    screenshotID: annotatedScreenshot.id,
                    label: "Submit button",
                    x: 0.42,
                    y: 0.56,
                    width: 0.22,
                    height: 0.16
                )
            ]
        )
        let artifactsDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = TranscriptSession(
            createdAt: Date(),
            transcript: "Transcript",
            duration: 30,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [annotatedScreenshot, plainScreenshot],
            issueExtraction: IssueExtractionResult(summary: "Summary", issues: [issue]),
            artifactsDirectoryPath: artifactsDirectory.path
        )

        let exports = try IssueScreenshotAnnotationRenderer()
            .annotatedScreenshotExports(for: issue, session: session)

        // The screenshot without annotations is filtered out.
        XCTAssertEqual(exports.count, 1)
        let export = try XCTUnwrap(exports.first)
        XCTAssertEqual(export.screenshotFileName, annotatedScreenshot.fileName)
        XCTAssertEqual(export.timeLabel, annotatedScreenshot.timeLabel)
        // Summaries are joined exactly as the providers render them.
        let expectedSummaries = issue.screenshotAnnotations(for: annotatedScreenshot.id)
            .map(\.exportDescription)
            .joined(separator: "; ")
        XCTAssertEqual(export.summaries, expectedSummaries)
        // An annotated asset was rendered into the artifacts directory.
        XCTAssertEqual(export.renderedFileName?.contains("annotated"), true)
    }
}

private func makeScreenshotFileURL(named fileName: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
    )!
    try? pngData.write(to: url)
    return url
}
