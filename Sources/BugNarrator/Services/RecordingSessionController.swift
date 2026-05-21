import Foundation

@MainActor
final class RecordingSessionStartStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    private let recordingStatusMessages: RecordingStatusMessageProvider
    private let startDiagnosticsMetadata: () -> [String: String]
    private let telemetryRecorder: any OperationalTelemetryRecording
    private let recordingLogger: DiagnosticsLogger
    private let permissionsLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        recordingStatusMessages: RecordingStatusMessageProvider,
        startDiagnosticsMetadata: @escaping () -> [String: String],
        telemetryRecorder: any OperationalTelemetryRecording,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording),
        permissionsLogger: DiagnosticsLogger = DiagnosticsLogger(category: .permissions)
    ) {
        self.errorPresenter = errorPresenter
        self.recordingStatusMessages = recordingStatusMessages
        self.startDiagnosticsMetadata = startDiagnosticsMetadata
        self.telemetryRecorder = telemetryRecorder
        self.recordingLogger = recordingLogger
        self.permissionsLogger = permissionsLogger
    }

    func present(_ outcome: RecordingSessionStartOutcome) {
        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStartIgnored, "The start request was ignored because another recording transition is already in progress.")

        case .busy:
            recordingLogger.warning(.sessionStartRejected, "The start request was rejected because BugNarrator is already busy.")

        case .restored(let recordingSession):
            recordingLogger.warning(
                "session_start_reconciled_active_session",
                "A start request arrived while a recording session draft was still active; restoring recording state instead of starting a duplicate recorder.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            errorPresenter.setStatus(.recording(recordingStatusMessages.recordingDetailMessage()))

        case .preflightFailure(let preflightError):
            permissionsLogger.warning(.sessionStartPreflightFailed, preflightError.userMessage)
            _ = errorPresenter.presentError(preflightError, operation: .recordingStart)

        case .failure(let error):
            _ = errorPresenter.presentError(error, operation: .recordingStart, fallback: { .recordingFailure($0) })

        case .started(let recordingSession):
            errorPresenter.setStatus(.recording(recordingStatusMessages.recordingDetailMessage()))
            let metadata = startDiagnosticsMetadata()
            var logMetadata = metadata
            logMetadata["session_id"] = recordingSession.sessionID.uuidString
            recordingLogger.info(
                .sessionStarted,
                "A feedback session started successfully.",
                metadata: logMetadata
            )
            telemetryRecorder.record(.recordingStarted, metadata: metadata)
        }
    }
}

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

@MainActor
final class RecordingSessionStopReadinessPresenter {
    private let errorPresenter: AppErrorPresenter
    private let recordingLogger: DiagnosticsLogger

    init(
        errorPresenter: AppErrorPresenter,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording)
    ) {
        self.errorPresenter = errorPresenter
        self.recordingLogger = recordingLogger
    }

    func recordingSession(for readiness: RecordingSessionStopReadiness) -> RecordingSessionDraft? {
        switch readiness {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStopIgnored, "The stop request was ignored because another recording transition is already in progress.")
            return nil

        case .noActiveRecording:
            recordingLogger.warning(.sessionStopRejected, "The stop request was rejected because no recording session is active.")
            return nil

        case .missingSessionMetadata:
            _ = errorPresenter.presentError(
                AppError.recordingFailure("The recording session metadata was unavailable."),
                operation: .recordingStop
            )
            return nil

        case .ready(let recordingSession):
            return recordingSession
        }
    }
}

@MainActor
final class RecordingSessionStopFailurePresenter {
    private let errorPresenter: AppErrorPresenter
    private let showSettingsWindow: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        showSettingsWindow: @escaping () -> Void
    ) {
        self.errorPresenter = errorPresenter
        self.showSettingsWindow = showSettingsWindow
    }

    func presentRecordingStopFailure(_ error: Error) {
        present(error, operation: .recordingStop, fallback: { .recordingFailure($0) })
    }

    func presentTranscriptionFailure(_ error: Error) {
        present(error, operation: .transcription)
    }

    func presentPreservationFailure(_ error: Error) {
        present(error, operation: .recordingStop)
    }

    private func present(
        _ error: Error,
        operation: AppErrorOperation,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        let result = errorPresenter.presentError(error, operation: operation, fallback: fallback)
        if result.shouldOpenSettingsWindow {
            showSettingsWindow()
        }
    }
}

@MainActor
final class RecordingSessionController: ObservableObject {
    @Published private(set) var activeRecordingSession: RecordingSessionDraft?

    private let audioRecorder: any AudioRecording
    private let microphonePermissionService: any MicrophonePermissionServicing
    private let artifactsService: any SessionArtifactsManaging
    private let recordingTimer: RecordingTimerViewModel
    private let recordingLogger: DiagnosticsLogger
    private let fileManager: FileManager

    private var processActivity: NSObjectProtocol?
    private var pendingRecordedAudio: RecordedAudio?
    private var transition: RecordingTransition = .idle

    init(
        audioRecorder: any AudioRecording,
        microphonePermissionService: any MicrophonePermissionServicing,
        artifactsService: any SessionArtifactsManaging,
        recordingTimer: RecordingTimerViewModel,
        recordingLogger: DiagnosticsLogger = DiagnosticsLogger(category: .recording),
        fileManager: FileManager = .default
    ) {
        self.audioRecorder = audioRecorder
        self.microphonePermissionService = microphonePermissionService
        self.artifactsService = artifactsService
        self.recordingTimer = recordingTimer
        self.recordingLogger = recordingLogger
        self.fileManager = fileManager
    }

    var currentDuration: TimeInterval {
        audioRecorder.currentDuration
    }

    var pendingRecordedAudioSnapshot: RecordedAudio? {
        pendingRecordedAudio
    }

    var hasActiveProcessActivity: Bool {
        processActivity != nil
    }

    func startSession(
        statusPhase: AppStatus.Phase,
        activityReason: String
    ) async -> RecordingSessionStartOutcome {
        guard transition == .idle else {
            return .transitionInProgress
        }

        transition = .starting
        defer { transition = .idle }

        guard statusPhase != .recording, statusPhase != .transcribing else {
            return .busy
        }

        if let activeRecordingSession {
            beginActivity(reason: activityReason)
            startTimer()
            return .restored(activeRecordingSession)
        }

        let preflightResult = await microphonePermissionService.preflightForRecordingStart(audioRecorder: audioRecorder)
        if let preflightError = preflightResult.error {
            return .preflightFailure(preflightError)
        }

        do {
            let sessionID = UUID()
            let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)

            do {
                try await audioRecorder.startRecording()
                pendingRecordedAudio = nil
                stopTimer(resetElapsed: true)
                let recordingSession = RecordingSessionDraft(
                    sessionID: sessionID,
                    artifactsDirectoryURL: artifactsDirectoryURL
                )
                activeRecordingSession = recordingSession
                beginActivity(reason: activityReason)
                startTimer()
                return .started(recordingSession)
            } catch {
                artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
                throw error
            }
        } catch {
            return .failure(error)
        }
    }

    func beginStoppingSession(statusPhase: AppStatus.Phase) -> RecordingSessionStopReadiness {
        guard transition == .idle else {
            return .transitionInProgress
        }

        guard statusPhase == .recording else {
            return .noActiveRecording
        }

        guard let activeRecordingSession else {
            return .missingSessionMetadata
        }

        transition = .stopping
        return .ready(activeRecordingSession)
    }

    func prepareForStopSession() {
        stopTimer(resetElapsed: false)
    }

    func stopRecording() async throws -> RecordedAudio {
        let recordedAudio = try await audioRecorder.stopRecording()
        pendingRecordedAudio = recordedAudio
        return recordedAudio
    }

    func finishStoppingSession() {
        transition = .idle
    }

    func cancelSession(
        preserveFile: Bool,
        onCancelWillBegin: () -> Void
    ) async -> RecordingSessionCancelOutcome {
        guard transition == .idle else {
            return .transitionInProgress
        }

        transition = .cancelling
        defer { transition = .idle }

        onCancelWillBegin()
        stopTimer(resetElapsed: true)
        endActivity()
        await audioRecorder.cancelRecording(preserveFile: preserveFile)

        let cancelledSession = activeRecordingSession
        if let cancelledSession {
            artifactsService.removeArtifactsDirectory(at: cancelledSession.artifactsDirectoryURL)
            activeRecordingSession = nil
        }

        pendingRecordedAudio = nil
        return .cancelled(cancelledSession)
    }

    func updateActiveRecordingSession(_ recordingSession: RecordingSessionDraft) {
        activeRecordingSession = recordingSession
    }

    func clearActiveRecordingSession() {
        activeRecordingSession = nil
    }

    func startTimer() {
        recordingTimer.start()
    }

    func stopTimer(resetElapsed: Bool) {
        recordingTimer.stop(resetElapsed: resetElapsed)
    }

    func beginActivity(reason: String) {
        endActivity()
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    func swapActivity(reason: String) {
        beginActivity(reason: reason)
    }

    func endActivity() {
        if let processActivity {
            ProcessInfo.processInfo.endActivity(processActivity)
        }

        processActivity = nil
    }

    func cleanupPendingRecordedAudioIfNeeded(debugMode: Bool) {
        guard let pendingRecordedAudio else {
            return
        }

        if !debugMode {
            try? fileManager.removeItem(at: pendingRecordedAudio.fileURL)
            recordingLogger.debug(
                "temporary_audio_removed",
                "Removed the temporary recorded audio file after use.",
                metadata: ["file_name": pendingRecordedAudio.fileURL.lastPathComponent]
            )
        } else {
            recordingLogger.debug(
                "temporary_audio_preserved",
                "Preserved the temporary recorded audio file because debug mode is enabled.",
                metadata: ["file_name": pendingRecordedAudio.fileURL.lastPathComponent]
            )
        }

        self.pendingRecordedAudio = nil
    }
}

private enum RecordingTransition {
    case idle
    case starting
    case stopping
    case cancelling
}

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
