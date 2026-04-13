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
}

private func makeScreenshotFileURL(named fileName: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(UUID().uuidString)-\(fileName)")
    let pngData = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////fwAJ+wP9KobjigAAAABJRU5ErkJggg=="
    )!
    try? pngData.write(to: url)
    return url
}
