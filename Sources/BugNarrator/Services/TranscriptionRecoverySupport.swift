import Foundation

enum PendingTranscriptionRetryResolution {
    case ready(PendingTranscriptionRetryContext)
    case duplicate
    case failure(AppError, opensSettings: Bool, statusMessage: String?)
}

struct PendingTranscriptionRetryFailure {
    let session: TranscriptSession
    let appError: AppError
    let statusMessage: String
}

enum RetryableSessionPreservationResult {
    case preserved(session: TranscriptSession, appError: AppError)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case preservationFailure(Error)
}
