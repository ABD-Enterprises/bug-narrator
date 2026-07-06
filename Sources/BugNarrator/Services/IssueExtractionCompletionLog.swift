import Foundation

struct IssueExtractionCompletionLog {
    let eventName: String
    let message: String

    static let manual = IssueExtractionCompletionLog(
        eventName: "issue_extraction_completed",
        message: "Issue extraction finished successfully."
    )

    static let postTranscription = IssueExtractionCompletionLog(
        eventName: "issue_extraction_completed_after_transcription",
        message: "Automatic issue extraction completed after transcription."
    )
}
