import XCTest
@testable import BugNarrator

/// Pure resolution logic between the review sheet and the export call (#1105).
final class IssueExportReviewPolicyTests: XCTestCase {

    // MARK: - preparedIssues

    func testExportNewPassesTheIssueThroughUnchanged() throws {
        let issue = makeIssue("Crash on launch")
        let review = makeReview(items: [IssueExportReviewItem(issue: issue, matches: [])])

        let prepared = try IssueExportReviewPolicy.preparedIssues(from: review)

        XCTAssertEqual(prepared, [issue])
        XCTAssertNil(prepared.first?.note)
    }

    func testLinkAsRelatedAttachesTheMatchNoteAndKeepsTheIssue() throws {
        let issue = makeIssue("Crash on launch")
        let match = makeMatch("ACME-42", title: "App crashes at startup", confidence: 0.86, reasoning: "Same stack trace.")
        let item = IssueExportReviewItem(issue: issue, matches: [match], resolution: .linkAsRelated)
        let review = makeReview(items: [item])

        let prepared = try IssueExportReviewPolicy.preparedIssues(from: review)

        XCTAssertEqual(prepared.count, 1)
        XCTAssertEqual(prepared.first?.id, issue.id)
        XCTAssertEqual(
            prepared.first?.note,
            "Related to ACME-42 (86% match): App crashes at startup. Same stack trace."
        )
    }

    func testLinkAsRelatedWithoutASelectedMatchThrowsNamingTheDestination() {
        var item = IssueExportReviewItem(issue: makeIssue("Crash"), matches: [], resolution: .linkAsRelated)
        item.selectedMatchID = nil
        let review = makeReview(destination: .jira, items: [item])

        XCTAssertThrowsError(try IssueExportReviewPolicy.preparedIssues(from: review)) { error in
            guard case .exportFailure(let message)? = error as? AppError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Choose a related Jira issue before linking.")
        }
    }

    func testMarkDuplicateDropsTheIssueFromTheExportSet() throws {
        let kept = makeIssue("Kept")
        let dropped = makeIssue("Dropped")
        let match = makeMatch("GH-7", title: "Existing", confidence: 1, reasoning: "Identical.")
        let review = makeReview(items: [
            IssueExportReviewItem(issue: kept, matches: []),
            IssueExportReviewItem(issue: dropped, matches: [match], resolution: .markDuplicate)
        ])

        let prepared = try IssueExportReviewPolicy.preparedIssues(from: review)

        XCTAssertEqual(prepared.map(\.id), [kept.id])
    }

    // MARK: - duplicateMatchResults

    func testDuplicateMatchResultsMapsOnlyMarkedItemsToTheirMatch() throws {
        let exported = makeIssue("Exported")
        let duplicate = makeIssue("Duplicate")
        let related = makeIssue("Related")
        let url = URL(string: "https://acme.atlassian.net/browse/ACME-9")
        let match = makeMatch("ACME-9", title: "Existing", confidence: 0.9, reasoning: "Same.", url: url)
        let review = makeReview(destination: .jira, items: [
            IssueExportReviewItem(issue: exported, matches: []),
            IssueExportReviewItem(issue: duplicate, matches: [match], resolution: .markDuplicate),
            IssueExportReviewItem(issue: related, matches: [match], resolution: .linkAsRelated)
        ])

        let results = try IssueExportReviewPolicy.duplicateMatchResults(from: review)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sourceIssueID, duplicate.id)
        XCTAssertEqual(results.first?.destination, .jira)
        XCTAssertEqual(results.first?.remoteIdentifier, "ACME-9")
        XCTAssertEqual(results.first?.remoteURL, url)
    }

    func testDuplicateMatchResultsWithoutASelectedMatchThrowsNamingTheDestination() {
        var item = IssueExportReviewItem(issue: makeIssue("Dup"), matches: [], resolution: .markDuplicate)
        item.selectedMatchID = nil
        let review = makeReview(destination: .github, items: [item])

        XCTAssertThrowsError(try IssueExportReviewPolicy.duplicateMatchResults(from: review)) { error in
            guard case .exportFailure(let message)? = error as? AppError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(message, "Choose an existing GitHub issue to mark as duplicate.")
        }
    }

    // MARK: - exportSummary

    func testSummaryWithCreatedAndLinkedCountsBoth() {
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(3), duplicateCount: 1, destination: .github),
            "Exported 2 new issues to GitHub and linked 1 to existing tracker items."
        )
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(2), duplicateCount: 1, destination: .jira),
            "Exported 1 new issue to Jira and linked 1 to existing tracker items."
        )
    }

    func testSummaryWithOnlyLinkedIssues() {
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(1), duplicateCount: 1, destination: .jira),
            "Linked 1 issue to existing Jira items without creating duplicates."
        )
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(2), duplicateCount: 2, destination: .github),
            "Linked 2 issues to existing GitHub items without creating duplicates."
        )
    }

    func testSummaryWithOnlyCreatedIssuesPluralizesLikeItsSiblings() {
        // The other two branches pluralize; this one said "Exported 1 issues".
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(1), duplicateCount: 0, destination: .github),
            "Exported 1 issue to GitHub."
        )
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(4), duplicateCount: 0, destination: .jira),
            "Exported 4 issues to Jira."
        )
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: [], duplicateCount: 0, destination: .jira),
            "Exported 0 issues to Jira."
        )
    }

    func testSummaryNeverReportsANegativeCreatedCount() {
        // duplicateCount larger than results is a caller bug; the summary must
        // still read sanely rather than say "Exported -1".
        XCTAssertEqual(
            IssueExportReviewPolicy.exportSummary(for: makeResults(1), duplicateCount: 2, destination: .github),
            "Linked 2 issues to existing GitHub items without creating duplicates."
        )
    }

    // MARK: - Helpers

    private func makeIssue(_ title: String) -> ExtractedIssue {
        ExtractedIssue(title: title, category: .bug, summary: "Summary", evidenceExcerpt: "Evidence", timestamp: nil)
    }

    private func makeMatch(_ id: String, title: String, confidence: Double, reasoning: String, url: URL? = nil) -> SimilarIssueMatch {
        SimilarIssueMatch(remoteIdentifier: id, title: title, summary: "", remoteURL: url, confidence: confidence, reasoning: reasoning)
    }

    private func makeReview(destination: ExportDestination = .github, items: [IssueExportReviewItem]) -> IssueExportReview {
        IssueExportReview(destination: destination, sessionID: UUID(), items: items)
    }

    private func makeResults(_ count: Int) -> [ExportResult] {
        (0..<count).map { index in
            ExportResult(sourceIssueID: UUID(), destination: .github, remoteIdentifier: "#\(index)", remoteURL: nil)
        }
    }
}
