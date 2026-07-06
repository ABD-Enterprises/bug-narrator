import Combine
import Foundation

@MainActor
final class RecordingSessionCancelStatusPresenter {
    static let discardedStatus = AppStatus.idle("Session discarded.")

    private let setStatus: (AppStatus) -> Void
    private let recordingLogger: DiagnosticsLogger

    init(
        setStatus: @escaping (AppStatus) -> Void,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording)
    ) {
        self.setStatus = setStatus
        self.recordingLogger = recordingLogger
    }

    func present(_ outcome: RecordingSessionCancelOutcome) {
        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug("session_cancel_ignored", "The cancel request was ignored because another recording transition is already in progress.")

        case .cancelled(let activeRecordingSession):
            if let activeRecordingSession {
                recordingLogger.info(
                    "session_cancelled",
                    "The active feedback session was discarded.",
                    metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
                )
            }
            setStatus(Self.discardedStatus)
        }
    }
}
