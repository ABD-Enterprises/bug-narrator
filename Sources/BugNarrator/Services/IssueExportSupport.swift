import Foundation

struct IssueExportPreflightFailure: Error {
    let error: AppError
    let opensSettings: Bool
}

struct IssueExportRequestContext {
    let destination: ExportDestination
    let session: TranscriptSession
    let selectedIssues: [ExtractedIssue]
    let apiKey: String
}

