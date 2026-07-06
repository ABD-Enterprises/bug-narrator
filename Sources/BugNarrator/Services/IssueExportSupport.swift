import Foundation

struct IssueExportPreflightFailure: Error {
    let error: AppError
    let opensSettings: Bool
}

struct IssueExportCompletion {
    let destination: ExportDestination
    let sessionID: UUID
    let results: [ExportResult]
    let duplicateCount: Int
    let performedRemoteExport: Bool

    var summary: String {
        IssueExportReviewPolicy.exportSummary(
            for: results,
            duplicateCount: duplicateCount,
            destination: destination
        )
    }
}
