import Foundation

enum PostTranscriptionPipelineResult {
    case success(TranscriptSession)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case postTranscriptionFailure(Error)
}
