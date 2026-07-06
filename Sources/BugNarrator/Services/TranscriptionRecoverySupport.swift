import Foundation

struct PendingTranscriptionRetryContext {
    let session: TranscriptSession
    let pendingTranscription: PendingTranscription
    let audioFileURL: URL
}

enum PendingTranscriptionRetryResolution {
    case ready(PendingTranscriptionRetryContext)
    case duplicate
    case failure(AppError, opensSettings: Bool, statusMessage: String?)
}

enum RetryableSessionPreservationResult {
    case preserved(session: TranscriptSession, appError: AppError)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case preservationFailure(Error)
}
