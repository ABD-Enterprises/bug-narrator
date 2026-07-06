import Foundation

enum RecordingSessionStartOutcome {
    case started(RecordingSessionDraft)
    case restored(RecordingSessionDraft)
    case transitionInProgress
    case busy
    case preflightFailure(AppError)
    case failure(Error)
}
