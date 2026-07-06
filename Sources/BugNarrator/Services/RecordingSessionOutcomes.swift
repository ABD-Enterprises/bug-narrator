import Foundation

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
