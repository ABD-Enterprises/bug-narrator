import Foundation
import XCTest

/// The review workspace's Screenshots gallery (#1270).
///
/// The gallery was rendered only while `session.issueExtraction == nil`, so
/// running issue extraction removed the user's own captured evidence from the
/// review surface: `screenshotsSection` has no other render site, and the
/// screenshots were reachable only when an individual extracted issue
/// happened to reference one.
///
/// This is a source-level assertion rather than a view test, because the
/// repository has no view-inspection harness. It pins the specific contract
/// that regressed — the gallery is not behind the issue-extraction condition —
/// and is written so that unrelated changes to the view do not break it.
final class ReviewWorkspaceScreenshotsSectionTests: XCTestCase {
    private func shellSource() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // BugNarratorTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        let url = root
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("BugNarrator", isDirectory: true)
            .appendingPathComponent("Views", isDirectory: true)
            .appendingPathComponent("Transcript", isDirectory: true)
            .appendingPathComponent("ReviewWorkspaceShell.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(url.path)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testTheScreenshotsGalleryIsNotHiddenWhenIssueExtractionRan() throws {
        let source = try shellSource()

        XCTAssertFalse(
            source.contains("issueExtraction == nil"),
            "The Screenshots gallery must not be hidden once issue extraction ran."
        )
        XCTAssertTrue(
            source.contains("reviewSectionCard(\"Screenshots\")"),
            "The Screenshots gallery must still be part of the review workspace."
        )
    }

    /// The gallery names the issues that reference each screenshot, so showing
    /// it alongside the extracted issues explains the duplication instead of
    /// looking like a stray copy.
    func testTheGalleryMarksTheIssuesThatReferenceAScreenshot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("BugNarrator", isDirectory: true)
            .appendingPathComponent("Views", isDirectory: true)
            .appendingPathComponent("Transcript", isDirectory: true)
            .appendingPathComponent("ScreenshotsSection.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Missing \(url.path)")
        let source = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(source.contains("relatedScreenshotIDs.contains(screenshot.id)"))
        XCTAssertTrue(source.contains("referencingIssues"))
    }
}
