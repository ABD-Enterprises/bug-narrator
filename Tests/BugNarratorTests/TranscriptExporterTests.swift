import XCTest
@testable import BugNarrator

@MainActor
final class TranscriptExporterTests: XCTestCase {
    func testWriteBundleCreatesExpectedFilesAndCopiesScreenshots() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let screenshotURL = rootDirectoryURL.appendingPathComponent("capture-1.png")
        try Data("image-data".utf8).write(to: screenshotURL, options: [.atomic])

        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: "The export button is missing on the reports page.",
            duration: 42,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [
                SessionMarker(index: 1, elapsedTime: 12, title: "Reports page", screenshotID: nil)
            ],
            screenshots: [
                SessionScreenshot(elapsedTime: 13, filePath: screenshotURL.path)
            ],
            issueExtraction: IssueExtractionResult(
                summary: "One bug in the reports page.",
                issues: [
                    ExtractedIssue(
                        title: "Export button missing",
                        category: .bug,
                        summary: "The reports page is missing an export button.",
                        evidenceExcerpt: "Export button is missing on reports page.",
                        timestamp: 13
                    )
                ]
            )
        )

        let exporter = TranscriptExporter(
            fileManager: fileManager,
            recentLogTextProvider: {
                "2026-03-15T12:00:00Z [INFO] [recording] session_started - Started a session.\n"
            }
        )
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)

        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("transcript.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("transcript.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("summary.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("recent-log.txt").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("screenshots").path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: bundleURL.appendingPathComponent("screenshots").appendingPathComponent("capture-1.png").path
            )
        )

        let plainText = try String(contentsOf: bundleURL.appendingPathComponent("transcript.txt"))
        XCTAssertTrue(plainText.contains("BugNarrator Transcript"))
        XCTAssertTrue(plainText.contains(session.transcript))

        let summaryMarkdown = try String(contentsOf: bundleURL.appendingPathComponent("summary.md"))
        XCTAssertTrue(summaryMarkdown.contains("# BugNarrator Review Output"))
        XCTAssertTrue(summaryMarkdown.contains("## Bug"))
        XCTAssertTrue(summaryMarkdown.contains("Export button missing"))

        let recentLog = try String(contentsOf: bundleURL.appendingPathComponent("recent-log.txt"))
        XCTAssertTrue(recentLog.contains("session_started"))
    }

    func testWriteBundleSkipsMissingScreenshotFilesButStillCreatesScreenshotsDirectory() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterMissingScreenshotsTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let missingScreenshotURL = rootDirectoryURL.appendingPathComponent("missing-capture.png")
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            transcript: "Transcript without an on-disk screenshot.",
            duration: 8,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [
                SessionScreenshot(elapsedTime: 4, filePath: missingScreenshotURL.path)
            ]
        )

        let exporter = TranscriptExporter(
            fileManager: fileManager,
            recentLogTextProvider: { "No recent BugNarrator diagnostics logs were captured.\n" }
        )
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)
        let screenshotsDirectoryURL = bundleURL.appendingPathComponent("screenshots", isDirectory: true)

        XCTAssertTrue(fileManager.fileExists(atPath: screenshotsDirectoryURL.path))
        let screenshotContents = try fileManager.contentsOfDirectory(atPath: screenshotsDirectoryURL.path)
        XCTAssertTrue(screenshotContents.isEmpty)
    }

    func testWriteBundleDoesNotOverwriteDuplicateScreenshotFileNames() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterDuplicateScreenshotTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let firstSourceDirectoryURL = rootDirectoryURL.appendingPathComponent("one", isDirectory: true)
        let secondSourceDirectoryURL = rootDirectoryURL.appendingPathComponent("two", isDirectory: true)
        try fileManager.createDirectory(at: firstSourceDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: secondSourceDirectoryURL, withIntermediateDirectories: true)

        let firstScreenshotURL = firstSourceDirectoryURL.appendingPathComponent("capture.png")
        let secondScreenshotURL = secondSourceDirectoryURL.appendingPathComponent("capture.png")
        try Data("first-image".utf8).write(to: firstScreenshotURL, options: [.atomic])
        try Data("second-image".utf8).write(to: secondScreenshotURL, options: [.atomic])

        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            transcript: "Transcript with screenshots that collide on export file name.",
            duration: 9,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [
                SessionScreenshot(elapsedTime: 2, filePath: firstScreenshotURL.path),
                SessionScreenshot(elapsedTime: 4, filePath: secondScreenshotURL.path)
            ]
        )

        let exporter = TranscriptExporter(
            fileManager: fileManager,
            recentLogTextProvider: { "No recent BugNarrator diagnostics logs were captured.\n" }
        )
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)
        let screenshotsDirectoryURL = bundleURL.appendingPathComponent("screenshots", isDirectory: true)
        let screenshotContents = try fileManager.contentsOfDirectory(atPath: screenshotsDirectoryURL.path).sorted()

        XCTAssertEqual(screenshotContents, ["capture-2.png", "capture.png"])
    }
}
