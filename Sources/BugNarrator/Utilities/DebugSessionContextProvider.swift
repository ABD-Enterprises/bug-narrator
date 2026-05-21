import Foundation

enum DebugSessionContextProvider {
    static func currentSessionID(
        activeRecordingSession: RecordingSessionDraft?,
        displayedTranscript: TranscriptSession?,
        currentTranscript: TranscriptSession?
    ) -> UUID? {
        activeRecordingSession?.sessionID ?? displayedTranscript?.id ?? currentTranscript?.id
    }

    static func metadata(
        currentTranscript: TranscriptSession?,
        displayedTranscript: TranscriptSession?,
        activeRecordingSession: RecordingSessionDraft?,
        status: AppStatus,
        currentError: AppError?
    ) -> DebugSessionMetadata {
        DebugSessionMetadata.make(
            currentTranscript: currentTranscript,
            displayedTranscript: displayedTranscript,
            activeRecordingSession: activeRecordingSession,
            status: status,
            currentError: currentError
        )
    }
}
