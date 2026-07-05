import Foundation

enum RecordingSessionStartOutcome {
    case started(RecordingSessionDraft)
    case restored(RecordingSessionDraft)
    case transitionInProgress
    case busy
    case preflightFailure(AppError)
    case failure(Error)
}

enum RecordingSessionStopReadiness {
    case ready(RecordingSessionDraft)
    case transitionInProgress
    case noActiveRecording
    case missingSessionMetadata
}

enum RecordingSessionCancelOutcome {
    case cancelled(RecordingSessionDraft?)
    case transitionInProgress
}
