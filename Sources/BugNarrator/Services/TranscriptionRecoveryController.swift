import Combine
import Foundation

@MainActor
final class TranscriptionRecoveryController: ObservableObject {
    @Published private(set) var retryingSessionID: UUID?

    private let sessionLibrary: SessionLibraryController
    private let artifactsService: any SessionArtifactsManaging
    private let fileManager: FileManager
    private let recordingLogger: DiagnosticsLogger
    private let transcriptionLogger: DiagnosticsLogger

    init(
        sessionLibrary: SessionLibraryController,
        artifactsService: any SessionArtifactsManaging,
        fileManager: FileManager = .default,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording),
        transcriptionLogger: DiagnosticsLogger = DiagnosticsLogger(category: .transcription)
    ) {
        self.sessionLibrary = sessionLibrary
        self.artifactsService = artifactsService
        self.fileManager = fileManager
        self.recordingLogger = recordingLogger
        self.transcriptionLogger = transcriptionLogger
    }

    func beginRetry(for sessionID: UUID) -> Bool {
        guard retryingSessionID == nil else {
            transcriptionLogger.warning(
                "transcription_retry_already_in_progress",
                "Ignoring duplicate retry request while a retry is already in progress.",
                metadata: [
                    "requested_session_id": sessionID.uuidString,
                    "active_retry_session_id": retryingSessionID?.uuidString ?? "unknown"
                ]
            )
            return false
        }

        retryingSessionID = sessionID
        return true
    }

    func finishRetry() {
        retryingSessionID = nil
    }

    func retryContext(
        for sessionID: UUID,
        isRecording: Bool,
        provider: AIProvider,
        hasUsableAIProviderCredential: Bool,
        aiProviderCompatibilityIssue: String?
    ) -> PendingTranscriptionRetryResolution {
        guard !isRecording else {
            return .failure(
                .recordingFailure("Stop the current recording before retrying transcription."),
                opensSettings: false,
                statusMessage: nil
            )
        }

        guard retryingSessionID == nil else {
            _ = beginRetry(for: sessionID)
            return .duplicate
        }

        guard let session = sessionLibrary.sessionSnapshot(with: sessionID),
              let pendingTranscription = session.pendingTranscription,
              let audioFileURL = session.pendingTranscriptionAudioURL else {
            return .failure(
                .transcriptionFailure("The saved retry session is unavailable."),
                opensSettings: false,
                statusMessage: nil
            )
        }

        guard pendingTranscription.failureReason != .crashRecovery else {
            return .failure(
                .transcriptionFailure("Unexpected-quit recording recovery is no longer supported. Delete this session and start a new recording."),
                opensSettings: false,
                statusMessage: "Unexpected-quit recording recovery is no longer supported. Delete this session and start a new recording."
            )
        }

        if let aiProviderCompatibilityIssue {
            return .failure(
                .transcriptionFailure(aiProviderCompatibilityIssue),
                opensSettings: true,
                statusMessage: session.transcriptionRetryMessage(for: provider) ?? aiProviderCompatibilityIssue
            )
        }

        guard hasUsableAIProviderCredential else {
            return .failure(
                .missingAPIKey,
                opensSettings: true,
                statusMessage: session.transcriptionRetryMessage(for: provider)
                    ?? AppError.missingAPIKey.userMessage(for: provider)
            )
        }

        guard fileManager.fileExists(atPath: audioFileURL.path) else {
            return .failure(
                .transcriptionFailure("The preserved audio file could not be found."),
                opensSettings: false,
                statusMessage: nil
            )
        }

        return .ready(
            PendingTranscriptionRetryContext(
                session: session,
                pendingTranscription: pendingTranscription,
                audioFileURL: audioFileURL
            )
        )
    }

    func recoverablePendingTranscriptionReason(for error: Error) -> PendingTranscriptionFailureReason? {
        guard let appError = error as? AppError else {
            return nil
        }

        return PendingTranscriptionFailureReason(appError: appError)
    }

    func recordRetryableFailure(
        _ error: Error,
        context: PendingTranscriptionRetryContext,
        provider: AIProvider
    ) -> PendingTranscriptionRetryFailure? {
        guard let failureReason = recoverablePendingTranscriptionReason(for: error) else {
            return nil
        }

        var session = context.session
        let pendingTranscription = context.pendingTranscription
        session.pendingTranscription = PendingTranscription(
            audioFileName: pendingTranscription.audioFileName,
            failureReason: failureReason,
            preservedAt: pendingTranscription.preservedAt,
            recoveredSourceFileName: pendingTranscription.recoveredSourceFileName,
            attemptCount: pendingTranscription.attemptCount + 1
        )

        do {
            try sessionLibrary.persistUpdatedSession(session)
        } catch {
            transcriptionLogger.error(
                "transcription_retry_state_persist_failed",
                "Retry attempt count could not be saved durably; pending transcription state is in memory only.",
                metadata: [
                    "session_id": session.id.uuidString,
                    "failure_reason": failureReason.rawValue,
                    "attempt_count": "\(session.pendingTranscription?.attemptCount ?? 0)",
                    "underlying_error": error.localizedDescription
                ]
            )
            sessionLibrary.stageCurrentTranscript(session)
        }

        finishRetry()

        let attemptMessage = pendingTranscription.attemptCount >= 2
            ? " This session has been retried \(pendingTranscription.attemptCount + 1) times."
            : ""
        return PendingTranscriptionRetryFailure(
            session: session,
            appError: failureReason.appError,
            statusMessage: (
                session.transcriptionRetryMessage(for: provider)
                    ?? failureReason.appError.userMessage(for: provider)
            ) + attemptMessage
        )
    }

    func preserveRetryableSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        failureReason: PendingTranscriptionFailureReason
    ) -> RetryableSessionPreservationResult {
        do {
            let preservedAudioURL = try preserveRecordedAudioForRetry(
                recordedAudio,
                in: recordingSession.artifactsDirectoryURL
            )
            let retryableSession = TranscriptionSessionBuilder.retryableSession(
                from: recordingSession,
                recordedAudio: recordedAudio,
                request: request,
                failureReason: failureReason,
                preservedAudioURL: preservedAudioURL
            )

            do {
                try sessionLibrary.persistRetryableSession(retryableSession)
            } catch {
                sessionLibrary.stageCurrentTranscript(retryableSession)
                return .persistenceFailure(session: retryableSession, error: error)
            }

            transcriptionLogger.warning(
                "transcription_deferred_for_retry",
                "Recording finished and was preserved for a later transcription retry.",
                metadata: [
                    "session_id": retryableSession.id.uuidString,
                    "failure_reason": failureReason.rawValue
                ]
            )
            return .preserved(session: retryableSession, appError: failureReason.appError)
        } catch {
            return .preservationFailure(error)
        }
    }

    func cleanupPreservedRetryAudioIfNeeded(at audioFileURL: URL, debugMode: Bool) {
        guard !debugMode else {
            recordingLogger.debug(
                "preserved_retry_audio_retained",
                "Kept the preserved retry audio because debug mode is enabled.",
                metadata: ["file_name": audioFileURL.lastPathComponent]
            )
            return
        }

        try? fileManager.removeItem(at: audioFileURL)
        recordingLogger.debug(
            "preserved_retry_audio_removed",
            "Removed the preserved retry audio after transcription succeeded.",
            metadata: ["file_name": audioFileURL.lastPathComponent]
        )
    }

    private func preserveRecordedAudioForRetry(
        _ recordedAudio: RecordedAudio,
        in artifactsDirectoryURL: URL
    ) throws -> URL {
        let preservedAudioURL = artifactsService.makeRecordedAudioURL(
            in: artifactsDirectoryURL,
            sourceFileURL: recordedAudio.fileURL
        )

        let sourceAlreadyPreserved = recordedAudio.fileURL.standardizedFileURL == preservedAudioURL.standardizedFileURL

        if !sourceAlreadyPreserved {
            if fileManager.fileExists(atPath: preservedAudioURL.path) {
                try fileManager.removeItem(at: preservedAudioURL)
            }

            try fileManager.copyItem(at: recordedAudio.fileURL, to: preservedAudioURL)
        }

        try validatePreservedAudio(at: preservedAudioURL)
        recordingLogger.info(
            "recorded_audio_preserved_for_retry",
            "Preserved the finished recording for a later transcription retry.",
            metadata: ["file_name": preservedAudioURL.lastPathComponent]
        )
        return preservedAudioURL
    }

    private func validatePreservedAudio(at preservedAudioURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: preservedAudioURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            try? fileManager.removeItem(at: preservedAudioURL)
            throw AppError.recordingFailure("The preserved audio file was empty.")
        }
    }

}
