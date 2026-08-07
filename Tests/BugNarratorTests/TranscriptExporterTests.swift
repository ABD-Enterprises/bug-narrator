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

        let exporter = TranscriptExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)

        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("transcript.md").path))
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("screenshots").path))
        XCTAssertTrue(
            fileManager.fileExists(
                atPath: bundleURL.appendingPathComponent("screenshots").appendingPathComponent("capture-1.png").path
            )
        )

        let markdown = try String(contentsOf: bundleURL.appendingPathComponent("transcript.md"))
        XCTAssertTrue(markdown.contains(session.transcript))
    }

    /// Replaces an earlier test that asserted export *threw* on a missing
    /// screenshot. #914 deliberately inverts that: one moved or pruned file must
    /// not make an otherwise complete session unexportable.
    func testWriteBundleDegradesWhenReferencedScreenshotFileIsMissing() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterMissingScreenshotsTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let presentScreenshotURL = rootDirectoryURL.appendingPathComponent("present-capture.png")
        try Data("image-data".utf8).write(to: presentScreenshotURL, options: [.atomic])
        let missingScreenshotURL = rootDirectoryURL.appendingPathComponent("missing-capture.png")

        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            transcript: "Transcript without an on-disk screenshot.",
            duration: 8,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            screenshots: [
                SessionScreenshot(elapsedTime: 4, filePath: presentScreenshotURL.path),
                SessionScreenshot(elapsedTime: 6, filePath: missingScreenshotURL.path)
            ]
        )

        let exporter = TranscriptExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)

        // The transcript still exports, and the screenshot that does exist is copied.
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("transcript.md").path))
        let screenshotsDirectoryURL = bundleURL.appendingPathComponent("screenshots")
        XCTAssertTrue(fileManager.fileExists(atPath: screenshotsDirectoryURL.appendingPathComponent("present-capture.png").path))
        XCTAssertFalse(fileManager.fileExists(atPath: screenshotsDirectoryURL.appendingPathComponent("missing-capture.png").path))

        // The absence is recorded rather than thrown.
        let manifestData = try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        XCTAssertEqual(manifest?["missingScreenshots"] as? [String], ["missing-capture.png"])
        XCTAssertEqual(manifest?["copiedScreenshotCount"] as? Int, 1)
        XCTAssertEqual(manifest?["screenshotCount"] as? Int, 2)
        XCTAssertEqual(
            manifest?["exportedFiles"] as? [String],
            ["transcript.md", "screenshots/present-capture.png", "manifest.json"],
            "exportedFiles must list what the bundle actually contains — the copied screenshot and the manifest included, the absent screenshot excluded."
        )
    }

    func testWriteBundleIncludesSummaryAndIssues() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            transcript: "The export button is missing on the reports page.",
            duration: 30,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
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

        let exporter = TranscriptExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)

        let summaryURL = bundleURL.appendingPathComponent("summary.md")
        XCTAssertTrue(fileManager.fileExists(atPath: summaryURL.path), "The differentiated output must be in the bundle, not just the raw transcript.")

        let summary = try String(contentsOf: summaryURL)
        XCTAssertTrue(summary.contains("One bug in the reports page."), "Expected the review summary.")
        XCTAssertTrue(summary.contains("Export button missing"), "Expected the extracted issue.")

        let manifestData = try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        XCTAssertEqual(
            manifest?["exportedFiles"] as? [String],
            ["transcript.md", "summary.md", "manifest.json"],
            "exportedFiles must record every file the bundle contains, manifest included."
        )
    }

    func testWriteBundleOmitsSummaryWhenExtractionNeverRan() throws {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptExporterNoSummaryTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootDirectoryURL) }

        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_300),
            transcript: "A session that never had issue extraction run.",
            duration: 12,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil
        )

        let exporter = TranscriptExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)

        XCTAssertFalse(
            fileManager.fileExists(atPath: bundleURL.appendingPathComponent("summary.md").path),
            "A session with no extraction should get no summary file rather than a placeholder saying extraction never ran."
        )
        XCTAssertTrue(fileManager.fileExists(atPath: bundleURL.appendingPathComponent("transcript.md").path))

        let manifestData = try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        XCTAssertEqual(
            manifest?["exportedFiles"] as? [String],
            ["transcript.md", "manifest.json"],
            "No summary.md when extraction never ran, but the manifest is still recorded."
        )
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

        let exporter = TranscriptExporter(fileManager: fileManager)
        let bundleURL = try exporter.writeBundle(session: session, to: rootDirectoryURL)
        let screenshotsDirectoryURL = bundleURL.appendingPathComponent("screenshots", isDirectory: true)
        let screenshotContents = try fileManager.contentsOfDirectory(atPath: screenshotsDirectoryURL.path).sorted()

        XCTAssertEqual(screenshotContents, ["capture-2.png", "capture.png"])
    }
}
