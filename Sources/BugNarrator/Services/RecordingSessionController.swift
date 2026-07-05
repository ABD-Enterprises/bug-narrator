import Foundation

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
