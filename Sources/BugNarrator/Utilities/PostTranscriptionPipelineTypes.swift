import Foundation

enum PostTranscriptionPipelineMode: Equatable {
    case finishedRecording
    case retry

    var savingAction: String {
        switch self {
        case .finishedRecording:
            return "Saving the finished session locally..."
        case .retry:
            return "Saving the retried session locally..."
        }
    }

    var recordsCompletionTelemetry: Bool {
        self == .finishedRecording
    }
}

enum PostTranscriptionPipelineResult {
    case success(TranscriptSession)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case postTranscriptionFailure(Error)
}
