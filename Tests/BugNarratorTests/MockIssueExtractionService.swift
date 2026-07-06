import Foundation
@testable import BugNarrator

actor MockIssueExtractionService: IssueExtracting {
    var result = IssueExtractionResult(summary: "", issues: [])

    func setResult(_ result: IssueExtractionResult) {
        self.result = result
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String,
        apiBaseURL: URL
    ) async throws -> IssueExtractionResult {
        result
    }
}
