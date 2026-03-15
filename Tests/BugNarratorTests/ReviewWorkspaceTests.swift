import Foundation
import XCTest
@testable import BugNarrator

final class ReviewWorkspaceTests: XCTestCase {
    func testAvailableTabsIncludeSummaryOnlyWhenSessionHasSummaryContent() {
        let baseSession = makeSession(summary: "", extraction: nil)
        let summarySession = makeSession(summary: "One summary line.", extraction: nil)
        let extractionSession = makeSession(
            summary: "",
            extraction: IssueExtractionResult(summary: "", issues: [])
        )

        XCTAssertEqual(
            ReviewWorkspace.availableTabs(for: baseSession),
            [.rawTranscript, .markers, .screenshots, .extractedIssues]
        )
        XCTAssertEqual(
            ReviewWorkspace.availableTabs(for: summarySession),
            [.rawTranscript, .markers, .screenshots, .extractedIssues, .reviewSummary]
        )
        XCTAssertEqual(
            ReviewWorkspace.availableTabs(for: extractionSession),
            [.rawTranscript, .markers, .screenshots, .extractedIssues, .reviewSummary]
        )
    }

    func testClampedTabFallsBackToTranscriptWhenSelectedTabIsUnavailable() {
        let baseSession = makeSession(summary: "", extraction: nil)

        XCTAssertEqual(
            ReviewWorkspace.clampedTab(.reviewSummary, for: baseSession),
            .rawTranscript
        )
        XCTAssertEqual(
            ReviewWorkspace.clampedTab(.screenshots, for: baseSession),
            .screenshots
        )
        XCTAssertEqual(
            ReviewWorkspace.clampedTab(.reviewSummary, for: nil),
            .rawTranscript
        )
    }

    func testTimelineEntriesSortMarkerAndScreenshotAheadOfTranscriptAtSameTimestamp() {
        let screenshotID = UUID()
        let marker = SessionMarker(
            index: 1,
            elapsedTime: 2,
            title: "Login page confusing",
            screenshotID: screenshotID
        )
        let screenshot = SessionScreenshot(
            id: screenshotID,
            elapsedTime: 2,
            filePath: "/tmp/capture-1.png",
            associatedMarkerID: marker.id
        )
        let section = TranscriptSection(
            title: "Observed issue",
            startTime: 2,
            endTime: 5,
            text: "The login page is confusing.",
            markerID: marker.id,
            screenshotIDs: [screenshotID]
        )
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: "The login page is confusing.",
            duration: 5,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            markers: [marker],
            screenshots: [screenshot],
            sections: [section]
        )

        let entries = ReviewWorkspace.timelineEntries(for: session)

        XCTAssertEqual(entries.map(\.kind), [.marker, .screenshot, .transcript])
        XCTAssertEqual(entries.map(\.text), ["Login page confusing", "Screenshot captured", "The login page is confusing."])
        XCTAssertEqual(entries[1].secondaryText, "Login page confusing")
    }

    func testSelectedIssueSummaryCountsOnlySelectedIssues() {
        let issues = [
            ExtractedIssue(
                title: "Export button missing",
                category: .bug,
                summary: "Export button missing on reports page.",
                evidenceExcerpt: "Export button is missing.",
                timestamp: 65,
                isSelectedForExport: true
            ),
            ExtractedIssue(
                title: "Login flow confusing",
                category: .uxIssue,
                summary: "Login flow is confusing.",
                evidenceExcerpt: "I can't find the reset link.",
                timestamp: 18,
                isSelectedForExport: false
            )
        ]
        let session = makeSession(
            summary: "Two issues found.",
            extraction: IssueExtractionResult(summary: "Two issues found.", issues: issues)
        )

        XCTAssertEqual(ReviewWorkspace.selectedIssueSummary(for: session), "1 issue selected")
    }

    private func makeSession(summary: String, extraction: IssueExtractionResult?) -> TranscriptSession {
        TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: "Hello session transcript.",
            duration: 5,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: extraction ?? (summary.isEmpty ? nil : IssueExtractionResult(summary: summary, issues: []))
        )
    }
}
