import Combine
import Foundation

@MainActor
final class RetryTranscriptionStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void
    private let showTranscriptWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void,
        showTranscriptWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
        self.showTranscriptWindow = showTranscriptWindow
    }

    func presentRetryStarted(progressMessage: String) {
        errorPresenter.setStatus(.transcribing(progressMessage))
    }

    func presentRetryContextFailure(
        appError: AppError,
        opensSettings: Bool,
        statusMessage: String?
    ) {
        if let statusMessage {
            errorPresenter.setStatus(.error(statusMessage), error: appError)
        } else {
            let result = errorPresenter.presentError(appError, operation: .retryTranscription)
            if result.shouldOpenSettingsWindow {
                showSettingsWindow()
            }
        }

        if opensSettings {
            showSettingsWindow()
        }
    }

    func presentRetryableFailure(_ failure: PendingTranscriptionRetryFailure) {
        errorPresenter.logAppError(
            failure.appError,
            context: "retry_pending_transcription",
            operation: .retryTranscription
        )
        errorPresenter.setStatus(.error(failure.statusMessage), error: failure.appError)
        showTranscriptWindow()
        showSettingsWindow()
    }

    func presentFailure(_ error: Error) {
        let result = errorPresenter.presentError(error, operation: .retryTranscription)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

@MainActor
final class PendingTranscriptionRetryFailureHandler {
    private let transcriptionRecovery: TranscriptionRecoveryController
    private let recordingSessionController: RecordingSessionController
    private let retryStatusPresenter: RetryTranscriptionStatusPresenter

    init(
        transcriptionRecovery: TranscriptionRecoveryController,
        recordingSessionController: RecordingSessionController,
        retryStatusPresenter: RetryTranscriptionStatusPresenter
    ) {
        self.transcriptionRecovery = transcriptionRecovery
        self.recordingSessionController = recordingSessionController
        self.retryStatusPresenter = retryStatusPresenter
    }

    func handle(_ error: Error, context: PendingTranscriptionRetryContext) {
        guard let retryFailure = transcriptionRecovery.recordRetryableFailure(error, context: context) else {
            transcriptionRecovery.finishRetry()
            retryStatusPresenter.presentFailure(error)
            return
        }

        recordingSessionController.endActivity()
        retryStatusPresenter.presentRetryableFailure(retryFailure)
    }
}

@MainActor
final class RetryableSessionPreservationPresenter {
    private let errorPresenter: AppErrorPresenter
    private let showTranscriptWindow: () -> Void
    private let showSettingsWindow: () -> Void
    private let sessionLibraryLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        showTranscriptWindow: @escaping () -> Void,
        showSettingsWindow: @escaping () -> Void,
        sessionLibraryLogger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.errorPresenter = errorPresenter
        self.showTranscriptWindow = showTranscriptWindow
        self.showSettingsWindow = showSettingsWindow
        self.sessionLibraryLogger = sessionLibraryLogger
    }

    func presentPreservedSession(_ retryableSession: TranscriptSession, appError: AppError) {
        errorPresenter.logAppError(appError, context: "preserve_retryable_session", operation: .transcription)
        errorPresenter.setStatus(
            .error(retryableSession.transcriptionRecoveryMessage ?? appError.userMessage),
            error: appError
        )
        showTranscriptWindow()
        if appError.suggestsOpenAISettings {
            showSettingsWindow()
        }
    }

    func presentPersistenceFailure(
        _ error: Error,
        retryableSession: TranscriptSession,
        recoveryAppError: AppError
    ) {
        let normalizedError = errorPresenter.normalizeError(
            error,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )
        let persistenceError = normalizedError.appError
        errorPresenter.logAppError(normalizedError, context: "retryable_session_persist_failed")
        var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "retryable_session_persist_failed")
        metadata["session_id"] = retryableSession.id.uuidString
        sessionLibraryLogger.error(
            "retryable_session_persist_failed",
            "The preserved recording could not be saved into local session history.",
            metadata: metadata
        )
        errorPresenter.setStatus(
            .error("Recording preserved, but \(persistenceError.userMessage)"),
            error: persistenceError
        )
        showTranscriptWindow()
        if recoveryAppError.suggestsOpenAISettings {
            showSettingsWindow()
        }
    }
}

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

        if let aiProviderCompatibilityIssue {
            return .failure(
                .transcriptionFailure(aiProviderCompatibilityIssue),
                opensSettings: true,
                statusMessage: aiProviderCompatibilityIssue
            )
        }

        guard hasUsableAIProviderCredential else {
            return .failure(
                .missingAPIKey,
                opensSettings: true,
                statusMessage: session.transcriptionRecoveryMessage ?? AppError.missingAPIKey.userMessage
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
        context: PendingTranscriptionRetryContext
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
            attemptCount: pendingTranscription.attemptCount + 1
        )

        do {
            try sessionLibrary.persistUpdatedSession(session)
        } catch {
            sessionLibrary.stageCurrentTranscript(session)
        }

        finishRetry()

        let attemptMessage = pendingTranscription.attemptCount >= 2
            ? " This session has been retried \(pendingTranscription.attemptCount + 1) times."
            : ""
        return PendingTranscriptionRetryFailure(
            session: session,
            appError: failureReason.appError,
            statusMessage: (session.transcriptionRecoveryMessage ?? failureReason.appError.userMessage) + attemptMessage
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

        if fileManager.fileExists(atPath: preservedAudioURL.path) {
            try fileManager.removeItem(at: preservedAudioURL)
        }

        if recordedAudio.fileURL.standardizedFileURL == preservedAudioURL.standardizedFileURL {
            return preservedAudioURL
        }

        try fileManager.copyItem(at: recordedAudio.fileURL, to: preservedAudioURL)

        let attributes = try fileManager.attributesOfItem(atPath: preservedAudioURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize > 0 else {
            throw AppError.recordingFailure("The preserved audio file was empty.")
        }

        recordingLogger.info(
            "recorded_audio_preserved_for_retry",
            "Preserved the finished recording for a later transcription retry.",
            metadata: ["file_name": preservedAudioURL.lastPathComponent]
        )
        return preservedAudioURL
    }

}

struct PendingTranscriptionRetryContext {
    let session: TranscriptSession
    let pendingTranscription: PendingTranscription
    let audioFileURL: URL
}

enum PendingTranscriptionRetryResolution {
    case ready(PendingTranscriptionRetryContext)
    case duplicate
    case failure(AppError, opensSettings: Bool, statusMessage: String?)
}

struct PendingTranscriptionRetryFailure {
    let session: TranscriptSession
    let appError: AppError
    let statusMessage: String
}

enum RetryableSessionPreservationResult {
    case preserved(session: TranscriptSession, appError: AppError)
    case persistenceFailure(session: TranscriptSession, error: Error)
    case preservationFailure(Error)
}
