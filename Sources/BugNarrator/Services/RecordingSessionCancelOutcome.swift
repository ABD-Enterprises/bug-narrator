import Foundation

enum RecordingSessionCancelOutcome {
    case cancelled(RecordingSessionDraft?)
    case transitionInProgress
}
