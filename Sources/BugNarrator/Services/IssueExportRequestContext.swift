import Foundation

struct IssueExportRequestContext {
    let destination: ExportDestination
    let session: TranscriptSession
    let selectedIssues: [ExtractedIssue]
    let apiKey: String
}
