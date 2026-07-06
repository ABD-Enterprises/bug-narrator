import Foundation

struct PendingTranscriptionRetryFailure {
    let session: TranscriptSession
    let appError: AppError
    let statusMessage: String
}
