import Foundation

struct PendingTranscriptionRetryContext {
    let session: TranscriptSession
    let pendingTranscription: PendingTranscription
    let audioFileURL: URL
}
