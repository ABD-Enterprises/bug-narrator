import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: AppStatus = .idle()
    @Published private(set) var currentError: AppError?
    @Published private(set) var transientToast: TransientToast?
    @Published private(set) var elapsedDuration: TimeInterval = 0
    @Published var showDiscardConfirmation = false
    @Published var currentTranscript: TranscriptSession?
    @Published var selectedTranscriptID: UUID?
    @Published private(set) var activeRecordingSession: RecordingSessionDraft?
    @Published private(set) var issueExtractionSessionID: UUID?
    @Published private(set) var exportDestinationInProgress: ExportDestination?
    @Published private(set) var pendingExportReview: IssueExportReview?
    @Published private(set) var apiKeyValidationState: APIKeyValidationState = .idle

    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore

    private let runtimeEnvironment: AppRuntimeEnvironment
    var showTranscriptWindow: (() -> Void)?
    var showSettingsWindow: (() -> Void)?
    var showAboutWindow: (() -> Void)?
    var showChangelogWindow: (() -> Void)?
    var showSupportWindow: (() -> Void)?
    var showRecordingControlWindow: (() -> Void)?
    var prepareForScreenshotSelection: (() -> Void)?
    var restoreAfterScreenshotSelection: (() -> Void)?

    private let audioRecorder: any AudioRecording
    private let microphonePermissionService: any MicrophonePermissionServicing
    private let screenCapturePermissionService: any ScreenCapturePermissionServicing
    private let transcriptionClient: any TranscriptionServing
    private let hotkeyManager: any HotkeyManaging
    private let screenshotCaptureService: any ScreenshotCapturing
    private let screenshotSelectionService: any ScreenshotSelecting
    private let issueExtractionService: any IssueExtracting
    private let exportService: any IssueExporting
    private let artifactsService: any SessionArtifactsManaging
    private let clipboardService: any ClipboardWriting
    private let urlHandler: any URLOpening
    private let debugBundleExporter = DebugBundleExporter()

    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let transcriptionLogger = DiagnosticsLogger(category: .transcription)
    private let sessionLibraryLogger = DiagnosticsLogger(category: .sessionLibrary)
    private let exportLogger = DiagnosticsLogger(category: .export)
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)
    private let screenshotLogger = DiagnosticsLogger(category: .screenshots)
    private let settingsLogger = DiagnosticsLogger(category: .settings)

    private var timerTask: Task<Void, Never>?
    private var processActivity: NSObjectProtocol?
    private var pendingRecordedAudio: RecordedAudio?
    private var cancellables = Set<AnyCancellable>()
    private var isStartingSession = false
    private var isStoppingSession = false
    private var isCancellingSession = false
    private var isValidatingAPIKey = false
    private var isCapturingScreenshot = false
    private var toastDismissTask: Task<Void, Never>?

    init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        audioRecorder: AudioRecording = AudioRecorder(),
        microphonePermissionService: any MicrophonePermissionServicing = MicrophonePermissionService(),
        screenCapturePermissionService: any ScreenCapturePermissionServicing = ScreenCapturePermissionService(),
        transcriptionClient: any TranscriptionServing = TranscriptionClient(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        screenshotCaptureService: any ScreenshotCapturing = ScreenshotCaptureService(),
        screenshotSelectionService: any ScreenshotSelecting = ScreenshotSelectionService(),
        issueExtractionService: any IssueExtracting = IssueExtractionService(),
        exportService: any IssueExporting = ExportService(),
        artifactsService: any SessionArtifactsManaging = SessionArtifactsService(),
        clipboardService: any ClipboardWriting = SystemClipboardService(),
        urlHandler: any URLOpening = WorkspaceURLHandler(),
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment()
    ) {
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.runtimeEnvironment = runtimeEnvironment
        self.audioRecorder = audioRecorder
        self.microphonePermissionService = microphonePermissionService
        self.screenCapturePermissionService = screenCapturePermissionService
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.screenshotCaptureService = screenshotCaptureService
        self.screenshotSelectionService = screenshotSelectionService
        self.issueExtractionService = issueExtractionService
        self.exportService = exportService
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.urlHandler = urlHandler
        self.selectedTranscriptID = transcriptStore.sessions.first?.id

        BugNarratorDiagnostics.setDebugModeEnabled(settingsStore.debugMode)

        self.hotkeyManager.onHotKeyPressed = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotKeyPressed(action)
            }
        }

        settingsStore.$startRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .startRecording)
            }
            .store(in: &cancellables)

        settingsStore.$stopRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .stopRecording)
            }
            .store(in: &cancellables)

        settingsStore.$screenshotHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .captureScreenshot)
            }
            .store(in: &cancellables)

        settingsStore.$apiKey
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.apiKeyValidationState = .idle
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshPermissionRecoveryState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.prepareForApplicationTermination()
            }
            .store(in: &cancellables)

        hotkeyManager.register(shortcut: settingsStore.startRecordingHotkeyShortcut, for: .startRecording)
        hotkeyManager.register(shortcut: settingsStore.stopRecordingHotkeyShortcut, for: .stopRecording)
        hotkeyManager.register(shortcut: settingsStore.screenshotHotkeyShortcut, for: .captureScreenshot)

        settingsLogger.info(
            "app_state_initialized",
            "BugNarrator finished initializing application state.",
            metadata: [
                "has_openai_key": settingsStore.hasAPIKey ? "yes" : "no",
                "debug_mode": settingsStore.debugMode ? "enabled" : "disabled"
            ]
        )
        validateRuntimeConfiguration()
        logLaunchDiagnostics()
    }

    var elapsedTimeString: String {
        ElapsedTimeFormatter.string(from: elapsedDuration)
    }

    var activeTimelineMomentCount: Int {
        activeRecordingSession?.markers.count ?? 0
    }

    var activeScreenshotCount: Int {
        activeRecordingSession?.screenshots.count ?? 0
    }

    var displayedTranscript: TranscriptSession? {
        if let selectedTranscriptID {
            if currentTranscript?.id == selectedTranscriptID {
                return currentTranscript
            }

            if let storedSession = transcriptStore.session(with: selectedTranscriptID) {
                return storedSession
            }
        }

        if let currentTranscript {
            return currentTranscript
        }

        return transcriptStore.sessions.first
    }

    var currentTranscriptIsPersisted: Bool {
        guard let currentTranscript else {
            return false
        }

        return transcriptStore.session(with: currentTranscript.id) == currentTranscript
    }

    var needsAPIKeySetup: Bool {
        !settingsStore.hasAPIKey
    }

    var preferredRecordingWorkflowSummary: String {
        "Open the recording controls window or use the global hotkeys while you keep testing."
    }

    var microphoneRecoveryGuidance: String {
        microphoneRecoveryGuidanceDetails.message
    }

    var microphoneRecoveryLocalTestingNote: String? {
        microphoneRecoveryGuidanceDetails.localTestingNote
    }

    var debugInfoSnapshot: DebugInfoSnapshot {
        DebugInfoSnapshot(
            metadata: BugNarratorMetadata(),
            settingsStore: settingsStore,
            sessionID: currentDebugSessionID
        )
    }

    func isExtractingIssues(for session: TranscriptSession) -> Bool {
        issueExtractionSessionID == session.id
    }

    func isExporting(to destination: ExportDestination) -> Bool {
        exportDestinationInProgress == destination
    }

    func refreshPermissionRecoveryState() {
        permissionsLogger.debug(
            "permission_recovery_refresh_started",
            "Refreshing permission recovery state after BugNarrator became active.",
            metadata: [
                "microphone_status": microphonePermissionService.currentStatus().rawValue,
                "screen_capture_status": screenCapturePermissionService.currentStatus().rawValue
            ]
        )

        switch currentError {
        case .microphonePermissionDenied, .microphonePermissionRestricted, .microphoneUnavailable:
            guard status.phase != .recording, status.phase != .transcribing else {
                return
            }

            let microphoneStatus = microphonePermissionService.currentStatus()
            guard microphoneStatus == .granted else {
                return
            }

            setStatus(.idle("Microphone access enabled. You can start recording again."))
        case .screenRecordingPermissionDenied:
            guard screenCapturePermissionService.currentStatus() == .granted else {
                return
            }

            if status.phase == .recording {
                setStatus(.recording("Screen Recording access enabled. You can capture screenshots again."))
            } else {
                setStatus(.idle("Screen Recording access enabled. You can capture screenshots again."))
            }
        default:
            return
        }
    }

    func canExportIssues(from session: TranscriptSession, to destination: ExportDestination) -> Bool {
        guard status.phase != .recording,
              status.phase != .transcribing,
              pendingExportReview == nil,
              let session = sessionSnapshot(with: session.id),
              let extraction = session.issueExtraction,
              !extraction.selectedIssues.isEmpty else {
            return false
        }

        switch destination {
        case .github:
            return settingsStore.githubExportConfiguration != nil
        case .jira:
            return settingsStore.jiraExportConfiguration != nil
        }
    }

    func startSession() async {
        recordingLogger.info("session_start_requested", "A feedback session start was requested.")

        guard !isStartingSession, !isStoppingSession, !isCancellingSession else {
            recordingLogger.debug("session_start_ignored", "The start request was ignored because another recording transition is already in progress.")
            return
        }

        guard status.phase != .recording, status.phase != .transcribing else {
            recordingLogger.warning("session_start_rejected", "The start request was rejected because BugNarrator is already busy.")
            return
        }

        let preflightResult = await preflightForSessionStart()
        if let preflightError = preflightResult.error {
            permissionsLogger.warning("session_start_preflight_failed", preflightError.userMessage)
            presentError(preflightError)
            return
        }

        isStartingSession = true
        defer { isStartingSession = false }

        do {
            if let activeRecordingSession {
                artifactsService.removeArtifactsDirectory(at: activeRecordingSession.artifactsDirectoryURL)
                self.activeRecordingSession = nil
            }

            let sessionID = UUID()
            let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)

            do {
                try await audioRecorder.startRecording()
                pendingRecordedAudio = nil
                elapsedDuration = 0
                activeRecordingSession = RecordingSessionDraft(
                    sessionID: sessionID,
                    artifactsDirectoryURL: artifactsDirectoryURL
                )
                let recordingDetail: String
                if settingsStore.hasAPIKey {
                    recordingDetail = "Recording in progress."
                } else {
                    recordingDetail = "Recording in progress. Add your OpenAI API key in Settings before stopping to transcribe this session."
                }

                setStatus(.recording(recordingDetail))
                beginActivity(reason: "Recording a spoken feedback session")
                startTimer()
                recordingLogger.info(
                    "session_started",
                    "A feedback session started successfully.",
                    metadata: [
                        "session_id": sessionID.uuidString,
                        "has_openai_key": settingsStore.hasAPIKey ? "yes" : "no"
                    ]
                )
            } catch {
                artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
                throw error
            }
        } catch {
            presentError(error)
        }
    }

    func stopSession() async {
        guard !isStoppingSession, !isCancellingSession else {
            recordingLogger.debug("session_stop_ignored", "The stop request was ignored because another recording transition is already in progress.")
            return
        }

        guard status.phase == .recording else {
            recordingLogger.warning("session_stop_rejected", "The stop request was rejected because no recording session is active.")
            return
        }

        guard let recordingSession = activeRecordingSession else {
            presentError(AppError.recordingFailure("The recording session metadata was unavailable."))
            return
        }

        isStoppingSession = true
        defer { isStoppingSession = false }

        stopTimer(resetElapsed: false)
        let request = makeTranscriptionRequest()

        do {
            recordingLogger.info(
                "session_stop_requested",
                "Stopping the active feedback session.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            let recordedAudio = try await audioRecorder.stopRecording()
            pendingRecordedAudio = recordedAudio

            guard settingsStore.hasAPIKey else {
                preserveRetryableSession(
                    from: recordingSession,
                    recordedAudio: recordedAudio,
                    request: request,
                    failureReason: .missingAPIKey
                )
                return
            }

            setStatus(.transcribing(transcriptionProgressMessage(step: 1, action: "Uploading audio to OpenAI for transcription...")))
            swapActivity(reason: "Uploading audio for transcription")

            let transcriptionResult = try await transcriptionClient.transcribe(
                fileURL: recordedAudio.fileURL,
                apiKey: settingsStore.trimmedAPIKey,
                request: request
            )

            let sections = TranscriptSectionBuilder.buildSections(
                transcript: transcriptionResult.text,
                segments: transcriptionResult.segments,
                markers: recordingSession.markers,
                duration: recordedAudio.duration
            )

            var session = TranscriptSession(
                id: recordingSession.sessionID,
                createdAt: Date(),
                transcript: transcriptionResult.text,
                duration: recordedAudio.duration,
                model: request.model,
                languageHint: request.languageHint,
                prompt: request.prompt,
                markers: recordingSession.markers,
                screenshots: recordingSession.screenshots,
                sections: sections,
                artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
            )

            transcriptionLogger.info(
                "transcription_completed",
                "BugNarrator finished transcription and created a transcript session.",
                metadata: [
                    "session_id": session.id.uuidString,
                    "marker_count": "\(session.markerCount)",
                    "screenshot_count": "\(session.screenshotCount)"
                ]
            )

            setStatus(.transcribing(transcriptionProgressMessage(step: 2, action: "Saving the finished session locally...")))

            do {
                try persistCompletedTranscript(session)
            } catch {
                currentTranscript = session
                selectedTranscriptID = session.id
                activeRecordingSession = nil
                if settingsStore.autoCopyTranscript {
                    clipboardService.copy(session.transcript)
                }
                cleanupPendingRecordedAudioIfNeeded()
                endActivity()
                let appError = (error as? AppError) ?? .storageFailure(error.localizedDescription)
                sessionLibraryLogger.error(
                    "transcript_persist_failed",
                    "Transcription succeeded, but saving the transcript locally failed.",
                    metadata: ["session_id": session.id.uuidString]
                )
                setStatus(.error("Transcript ready, but \(appError.userMessage)"), error: appError)
                showTranscriptWindow?()
                return
            }

            currentTranscript = session
            activeRecordingSession = nil
            showTranscriptWindow?()

            if settingsStore.autoExtractIssues {
                issueExtractionSessionID = session.id
                setStatus(.transcribing(transcriptionProgressMessage(step: 3, action: "Extracting reviewable issues...")))
                swapActivity(reason: "Extracting review issues")

                do {
                    let extraction = try await issueExtractionService.extractIssues(
                        from: session,
                        apiKey: settingsStore.trimmedAPIKey,
                        model: settingsStore.issueExtractionModelValue
                    )
                    session.issueExtraction = extraction
                    try persistUpdatedSession(session)
                    transcriptionLogger.info(
                        "issue_extraction_completed_after_transcription",
                        "Automatic issue extraction completed after transcription.",
                        metadata: [
                            "session_id": session.id.uuidString,
                            "issue_count": "\(extraction.issues.count)"
                        ]
                    )
                } catch {
                    cleanupPendingRecordedAudioIfNeeded()
                    endActivity()
                    issueExtractionSessionID = nil
                    presentPostTranscriptionError(error)
                    return
                }

                issueExtractionSessionID = nil
            }

            cleanupPendingRecordedAudioIfNeeded()
            endActivity()
            setStatus(.success(
                settingsStore.autoExtractIssues
                    ? "Session saved. Transcript and extracted issues are ready."
                    : (settingsStore.autoCopyTranscript
                        ? "Session saved. Transcript copied to the clipboard."
                        : "Session saved locally and ready for review.")
            ))
        } catch {
            if let failureReason = recoverablePendingTranscriptionReason(for: error),
               let recordedAudio = pendingRecordedAudio {
                preserveRetryableSession(
                    from: recordingSession,
                    recordedAudio: recordedAudio,
                    request: request,
                    failureReason: failureReason
                )
                return
            }

            if !settingsStore.debugMode {
                artifactsService.removeArtifactsDirectory(at: recordingSession.artifactsDirectoryURL)
            }
            activeRecordingSession = nil
            presentError(error)
        }
    }

    func requestSessionCancel() {
        guard status.phase == .recording else {
            return
        }

        showDiscardConfirmation = true
    }

    func cancelSession() async {
        guard !isCancellingSession, !isStoppingSession else {
            recordingLogger.debug("session_cancel_ignored", "The cancel request was ignored because another recording transition is already in progress.")
            return
        }

        isCancellingSession = true
        defer { isCancellingSession = false }

        showDiscardConfirmation = false
        stopTimer(resetElapsed: true)
        endActivity()
        await audioRecorder.cancelRecording(preserveFile: settingsStore.debugMode)
        if let activeRecordingSession {
            artifactsService.removeArtifactsDirectory(at: activeRecordingSession.artifactsDirectoryURL)
            self.activeRecordingSession = nil
            recordingLogger.info(
                "session_cancelled",
                "The active feedback session was discarded.",
                metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
            )
        }
        pendingRecordedAudio = nil
        setStatus(.idle("Session discarded."))
    }

    func openTranscriptHistory() {
        showTranscriptWindow?()
    }

    func openRecordingControls() {
        showRecordingControlWindow?()
    }

    func openRecordingControlsAndStartSession() async {
        showRecordingControlWindow?()

        guard status.phase != .recording else {
            return
        }

        await startSession()
    }

    func openSettings() {
        settingsLogger.debug("open_settings", "Opening the Settings window.")
        showSettingsWindow?()
    }

    func requestApplicationTermination() {
        guard applicationShouldTerminate() == .terminateNow else {
            return
        }

        NSApp.terminate(nil)
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        guard status.phase == .recording,
              let activeRecordingSession else {
            return .terminateNow
        }

        recordingLogger.warning(
            "termination_blocked_while_recording",
            "BugNarrator blocked an app termination request while a recording session was still active.",
            metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
        )
        showRecordingControlWindow?()
        showToast("Stop recording before quitting BugNarrator.", style: .informational)
        return .terminateCancel
    }

    func openAbout() {
        showAboutWindow?()
    }

    func openChangelog() {
        showChangelogWindow?()
    }

    func openGitHubRepository() {
        openExternalURL(BugNarratorLinks.repository, label: "GitHub repository")
    }

    func openDocumentation() {
        openExternalURL(BugNarratorLinks.documentation, label: "documentation")
    }

    func openIssueReporter() {
        openExternalURL(BugNarratorLinks.issues, label: "issue tracker")
    }

    func openSupportDevelopment() {
        showSupportWindow?()
    }

    func openSupportDonationPage() {
        openExternalURL(BugNarratorLinks.supportDevelopment, label: "PayPal donation page")
    }

    func openMicrophonePrivacySettings() {
        let candidateURLs = [
            BugNarratorLinks.microphonePrivacySettings,
            BugNarratorLinks.securityPrivacySettings,
            BugNarratorLinks.systemSettingsApp
        ]

        for url in candidateURLs where urlHandler.open(url) {
            return
        }

        presentUtilityActionFailure("BugNarrator could not open Microphone settings automatically.")
    }

    func openScreenRecordingPrivacySettings() {
        let candidateURLs = [
            BugNarratorLinks.screenRecordingPrivacySettings,
            BugNarratorLinks.securityPrivacySettings,
            BugNarratorLinks.systemSettingsApp
        ]

        for url in candidateURLs where urlHandler.open(url) {
            return
        }

        presentUtilityActionFailure("BugNarrator could not open Screen Recording settings automatically.")
    }

    func checkForUpdates() {
        openExternalURL(BugNarratorLinks.releases, label: "releases page")
    }

    func copyDebugInfo() {
        let snapshot = debugInfoSnapshot
        clipboardService.copy(snapshot.clipboardText)
        settingsLogger.info(
            "debug_info_copied",
            "Copied debug info to the clipboard.",
            metadata: ["session_id": snapshot.sessionID?.uuidString ?? "none"]
        )
        setStatus(.success("Debug info copied to the clipboard."))
    }

    func exportDebugBundle() async {
        let snapshot = await makeDebugBundleSnapshot()

        do {
            guard let bundleURL = try debugBundleExporter.export(snapshot: snapshot) else {
                return
            }

            settingsLogger.info(
                "debug_bundle_exported",
                "Exported a local debug bundle.",
                metadata: [
                    "session_id": snapshot.sessionMetadata.sessionID?.uuidString ?? "none",
                    "debug_mode": snapshot.debugInfo.debugModeEnabled ? "enabled" : "disabled"
                ]
            )
            NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
            setStatus(
                .success(
                    settingsStore.debugMode
                        ? "Debug bundle exported with verbose diagnostics."
                        : "Debug bundle exported."
                )
            )
        } catch {
            let appError = (error as? AppError) ?? .diagnosticsFailure("BugNarrator could not create the debug bundle.")
            presentError(appError)
        }
    }

    func validateAPIKey() async {
        guard !isValidatingAPIKey else {
            return
        }

        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard settingsStore.hasAPIKey else {
            settingsLogger.warning("validate_openai_key_rejected", "OpenAI key validation was requested without a saved key.")
            apiKeyValidationState = .failure(AppError.missingAPIKey.userMessage)
            showSettingsWindow?()
            return
        }

        isValidatingAPIKey = true
        apiKeyValidationState = .validating
        defer { isValidatingAPIKey = false }

        do {
            try await transcriptionClient.validateAPIKey(settingsStore.trimmedAPIKey)
            apiKeyValidationState = .success("OpenAI accepted this key.")
            settingsLogger.info("validate_openai_key_succeeded", "The OpenAI API key validation flow succeeded.")
        } catch {
            let appError = (error as? AppError) ?? .transcriptionFailure(error.localizedDescription)
            apiKeyValidationState = .failure(appError.userMessage)
            settingsLogger.warning("validate_openai_key_failed", appError.userMessage)
        }
    }

    func removeAPIKey() {
        settingsStore.removeAPIKey()
        apiKeyValidationState = .idle
        settingsLogger.info("openai_key_removed", "The user removed the OpenAI API key.")
    }

    func copyDisplayedTranscript() {
        guard let transcript = displayedTranscript else {
            return
        }

        guard transcript.hasTranscriptContent else {
            setStatus(.error("Transcription is not available yet. Retry the preserved session first."))
            return
        }

        clipboardService.copy(transcript.transcript)
        setStatus(.success("Transcript copied to the clipboard."))
    }

    func retryPendingTranscription(for sessionID: UUID) async {
        guard status.phase != .recording else {
            presentError(AppError.recordingFailure("Stop the current recording before retrying transcription."))
            return
        }

        guard var session = sessionSnapshot(with: sessionID),
              let pendingTranscription = session.pendingTranscription,
              let audioFileURL = session.pendingTranscriptionAudioURL else {
            presentError(AppError.transcriptionFailure("The saved retry session is unavailable."))
            return
        }

        guard settingsStore.hasAPIKey else {
            setStatus(.error(
                session.transcriptionRecoveryMessage ?? AppError.missingAPIKey.userMessage
            ), error: .missingAPIKey)
            showSettingsWindow?()
            return
        }

        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            presentError(AppError.transcriptionFailure("The preserved audio file could not be found."))
            return
        }

        let request = makeTranscriptionRequest()
        selectedTranscriptID = session.id
        currentTranscript = session
        setStatus(.transcribing(transcriptionProgressMessage(step: 1, action: "Retrying transcription from the preserved recording...")))
        swapActivity(reason: "Retrying transcription from preserved audio")
        transcriptionLogger.info(
            "transcription_retry_requested",
            "Retrying transcription from preserved audio.",
            metadata: [
                "session_id": session.id.uuidString,
                "failure_reason": pendingTranscription.failureReason.rawValue
            ]
        )

        do {
            let result = try await transcriptionClient.transcribe(
                fileURL: audioFileURL,
                apiKey: settingsStore.trimmedAPIKey,
                request: request
            )

            let sections = TranscriptSectionBuilder.buildSections(
                transcript: result.text,
                segments: result.segments,
                markers: session.markers,
                duration: session.duration
            )

            var updatedSession = TranscriptSession(
                id: session.id,
                createdAt: session.createdAt,
                transcript: result.text,
                duration: session.duration,
                model: request.model,
                languageHint: request.languageHint,
                prompt: request.prompt,
                markers: session.markers,
                screenshots: session.screenshots,
                sections: sections,
                issueExtraction: nil,
                pendingTranscription: nil,
                updatedAt: Date(),
                artifactsDirectoryPath: session.artifactsDirectoryPath
            )

            setStatus(.transcribing(transcriptionProgressMessage(step: 2, action: "Saving the recovered session locally...")))
            try persistUpdatedSession(updatedSession)

            if settingsStore.autoCopyTranscript {
                clipboardService.copy(updatedSession.transcript)
            }

            if settingsStore.autoExtractIssues {
                issueExtractionSessionID = updatedSession.id
                setStatus(.transcribing(transcriptionProgressMessage(step: 3, action: "Extracting reviewable issues...")))
                swapActivity(reason: "Extracting review issues")

                do {
                    let extraction = try await issueExtractionService.extractIssues(
                        from: updatedSession,
                        apiKey: settingsStore.trimmedAPIKey,
                        model: settingsStore.issueExtractionModelValue
                    )
                    updatedSession.issueExtraction = extraction
                    try persistUpdatedSession(updatedSession)
                } catch {
                    cleanupPreservedRetryAudioIfNeeded(at: audioFileURL)
                    endActivity()
                    issueExtractionSessionID = nil
                    presentPostTranscriptionError(error)
                    return
                }

                issueExtractionSessionID = nil
            }

            cleanupPreservedRetryAudioIfNeeded(at: audioFileURL)
            showTranscriptWindow?()
            endActivity()
            setStatus(.success(
                settingsStore.autoExtractIssues
                    ? "Session saved. Transcript and extracted issues are ready."
                    : (settingsStore.autoCopyTranscript
                        ? "Session saved. Transcript copied to the clipboard."
                        : "Session saved locally and ready for review.")
            ))
        } catch {
            if let failureReason = recoverablePendingTranscriptionReason(for: error) {
                session.pendingTranscription = PendingTranscription(
                    audioFileName: pendingTranscription.audioFileName,
                    failureReason: failureReason,
                    preservedAt: pendingTranscription.preservedAt
                )

                do {
                    try persistUpdatedSession(session)
                } catch {
                    currentTranscript = session
                    selectedTranscriptID = session.id
                }

                endActivity()
                let appError = failureReason.appError
                logAppError(appError, context: "retry_pending_transcription")
                setStatus(.error(
                    session.transcriptionRecoveryMessage ?? appError.userMessage
                ), error: appError)
                showTranscriptWindow?()
                showSettingsWindow?()
                return
            }

            presentError(error)
        }
    }

    func saveCurrentTranscriptToHistory() {
        guard let currentTranscript, !currentTranscriptIsPersisted else {
            selectedTranscriptID = currentTranscript?.id
            return
        }

        do {
            try transcriptStore.add(currentTranscript)
            selectedTranscriptID = currentTranscript.id
            sessionLibraryLogger.info(
                "unsaved_transcript_persisted",
                "Saved the in-memory transcript into local session history.",
                metadata: ["session_id": currentTranscript.id.uuidString]
            )
            setStatus(.success("Transcript saved to session history."))
        } catch {
            presentError(error)
        }
    }

    func deleteDisplayedTranscript() {
        guard let displayedTranscript else {
            return
        }

        deleteSessions(withIDs: [displayedTranscript.id])
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        let wasSelectedTranscriptDeleted = selectedTranscriptID.map(ids.contains) ?? false
        let deletingUnsavedCurrentTranscript = currentTranscript
            .map { ids.contains($0.id) && transcriptStore.session(with: $0.id) == nil }
            ?? false

        do {
            let removedSessions = try transcriptStore.removeSessions(withIDs: ids)
            var sessionsToCleanup = removedSessions
            if let currentTranscript,
               ids.contains(currentTranscript.id),
               !removedSessions.contains(where: { $0.id == currentTranscript.id }),
               transcriptStore.session(with: currentTranscript.id) == nil {
                sessionsToCleanup.append(currentTranscript)
            }
            sessionsToCleanup.forEach(cleanupArtifactsForDeletedSession)

            if currentTranscript.map({ ids.contains($0.id) }) == true {
                currentTranscript = nil
            }

            if wasSelectedTranscriptDeleted || selectedTranscriptID == nil {
                selectedTranscriptID = preferredTranscriptSelection()
            }

            let deletedCount = removedSessions.count + (deletingUnsavedCurrentTranscript ? 1 : 0)
            if deletedCount > 0 {
                sessionLibraryLogger.info(
                    "sessions_deleted_from_library",
                    "Deleted sessions from the library.",
                    metadata: ["deleted_count": "\(deletedCount)"]
                )
                setStatus(.success(deletedCount == 1 ? "Deleted 1 session." : "Deleted \(deletedCount) sessions."))
            }
        } catch {
            presentError(error)
        }
    }

    func captureScreenshot() async {
        guard status.phase == .recording, let recordingSession = activeRecordingSession else {
            let error = AppError.noActiveSession("Start a feedback session before capturing a screenshot.")
            screenshotLogger.warning("screenshot_rejected_no_session", error.userMessage)
            setStatus(.error(error.userMessage), error: error)
            return
        }

        if isCapturingScreenshot {
            let error = AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
            screenshotLogger.warning("screenshot_rejected_busy", error.userMessage)
            setStatus(.recording(error.userMessage), error: error)
            return
        }

        let screenshotIndex = recordingSession.screenshots.count + 1
        let markerIndex = recordingSession.markers.count + 1
        let elapsedTime = max(audioRecorder.currentDuration, elapsedDuration)
        let markerID = UUID()
            let markerTitle = "Screenshot \(screenshotIndex)"

        do {
            let screenshot = try await performScreenshotCapture(
                in: recordingSession,
                prefix: "capture",
                index: screenshotIndex,
                elapsedTime: elapsedTime,
                associatedMarkerID: markerID
            )
            guard let screenshot else {
                guard status.phase == .recording,
                      activeRecordingSession?.sessionID == recordingSession.sessionID else {
                    return
                }
                showToast("Screenshot canceled", style: .informational)
                return
            }
            guard status.phase == .recording,
                  var latestRecordingSession = activeRecordingSession,
                  latestRecordingSession.sessionID == recordingSession.sessionID else {
                return
            }
            latestRecordingSession.markers.append(
                SessionMarker(
                    id: markerID,
                    index: markerIndex,
                    elapsedTime: elapsedTime,
                    title: markerTitle,
                    note: nil,
                    screenshotID: screenshot.id
                )
            )
            latestRecordingSession.screenshots.append(screenshot)
            activeRecordingSession = latestRecordingSession
            screenshotLogger.info(
                "screenshot_captured",
                "Captured a screenshot and inserted the automatic marker.",
                metadata: [
                    "session_id": recordingSession.sessionID.uuidString,
                    "screenshot_index": "\(screenshotIndex)",
                    "marker_index": "\(markerIndex)"
                ]
            )
            setStatus(.recording("Captured \(markerTitle)."))
            showToast("Screenshot captured")
        } catch {
            let appError = (error as? AppError) ?? .screenshotCaptureFailure(error.localizedDescription)
            guard status.phase == .recording else {
                return
            }
            screenshotLogger.error(
                "screenshot_capture_failed",
                appError.userMessage,
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            setStatus(.recording(appError.userMessage), error: appError)
        }
    }

    private func transcriptionProgressMessage(step: Int, action: String) -> String {
        let totalSteps = settingsStore.autoExtractIssues ? 3 : 2
        return "Step \(step) of \(totalSteps): \(action)"
    }

    func extractIssuesForDisplayedTranscript() async {
        guard let transcriptSession = displayedTranscript else {
            return
        }

        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard let preflightError = preflightForIssueExtraction(transcriptSession) else {
            issueExtractionSessionID = transcriptSession.id
            setStatus(.transcribing("Running issue extraction with a 10-second time limit..."))
            beginActivity(reason: "Extracting review issues")
            transcriptionLogger.info(
                "issue_extraction_requested",
                "Issue extraction was requested for the selected transcript.",
                metadata: ["session_id": transcriptSession.id.uuidString]
            )

            do {
                let extraction = try await issueExtractionService.extractIssues(
                    from: transcriptSession,
                    apiKey: settingsStore.trimmedAPIKey,
                    model: settingsStore.issueExtractionModelValue
                )

                var updatedSession = transcriptSession
                updatedSession.issueExtraction = extraction
                try persistUpdatedSession(updatedSession)

                issueExtractionSessionID = nil
                endActivity()
                transcriptionLogger.info(
                    "issue_extraction_completed",
                    "Issue extraction finished successfully.",
                    metadata: [
                        "session_id": transcriptSession.id.uuidString,
                        "issue_count": "\(extraction.issues.count)"
                    ]
                )
                setStatus(.success("Extracted \(extraction.issues.count) review issues."))
                showTranscriptWindow?()
            } catch {
                issueExtractionSessionID = nil
                presentError(error)
            }

            return
        }

        transcriptionLogger.warning(
            "issue_extraction_preflight_failed",
            preflightError.userMessage,
            metadata: ["session_id": transcriptSession.id.uuidString]
        )
        presentError(preflightError)
    }

    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == updatedIssue.id }) else {
            return
        }

        extraction.issues[issueIndex] = updatedIssue
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction,
              let issueIndex = extraction.issues.firstIndex(where: { $0.id == issueID }) else {
            return
        }

        extraction.issues[issueIndex].isSelectedForExport = isSelected
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) {
        guard var session = editableSession(with: sessionID),
              var extraction = session.issueExtraction else {
            return
        }

        extraction.issues = extraction.issues.map { issue in
            var updatedIssue = issue
            updatedIssue.isSelectedForExport = isSelected
            return updatedIssue
        }
        session.issueExtraction = extraction

        do {
            try persistUpdatedSession(session)
        } catch {
            presentError(error)
        }
    }

    func exportSelectedIssues(from session: TranscriptSession, to destination: ExportDestination) async {
        guard status.phase != .recording, status.phase != .transcribing else {
            presentError(AppError.exportFailure("Finish the current background work before exporting issues."))
            return
        }

        guard let currentSession = sessionSnapshot(with: session.id) else {
            presentError(AppError.exportFailure("This session is no longer available in the library."))
            return
        }

        guard let extraction = currentSession.issueExtraction else {
            presentError(AppError.exportFailure("Run issue extraction before exporting."))
            return
        }

        let selectedIssues = extraction.selectedIssues
        guard !selectedIssues.isEmpty else {
            presentError(AppError.exportFailure("Select at least one extracted issue to export."))
            return
        }

        settingsStore.refreshExportSecretsForUserInitiatedAccess()

        do {
            try validateExportConfiguration(for: destination)
        } catch {
            presentError(error)
            if case .exportConfigurationMissing = error as? AppError {
                showSettingsWindow?()
            }
            return
        }

        guard settingsStore.hasAPIKey else {
            presentError(AppError.missingAPIKey)
            return
        }

        exportDestinationInProgress = destination
        setStatus(.transcribing("Checking \(destination.rawValue) for similar open issues..."))
        beginActivity(reason: "Reviewing similar issues before export")
        exportLogger.info(
            "issue_export_review_requested",
            "Preparing similar issue review before export.",
            metadata: [
                "destination": destination.rawValue,
                "session_id": currentSession.id.uuidString,
                "issue_count": "\(selectedIssues.count)"
            ]
        )

        do {
            let review: IssueExportReview

            switch destination {
            case .github:
                guard let configuration = settingsStore.githubExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "GitHub export requires a token, repository owner, and repository name."
                    )
                }
                review = try await exportService.prepareGitHubExportReview(
                    issues: selectedIssues,
                    session: currentSession,
                    configuration: configuration,
                    apiKey: settingsStore.trimmedAPIKey,
                    model: settingsStore.issueExtractionModelValue
                )
            case .jira:
                guard let configuration = settingsStore.jiraExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "Jira export requires a base URL, email, API token, project key, and issue type."
                    )
                }
                review = try await exportService.prepareJiraExportReview(
                    issues: selectedIssues,
                    session: currentSession,
                    configuration: configuration,
                    apiKey: settingsStore.trimmedAPIKey,
                    model: settingsStore.issueExtractionModelValue
                )
            }

            exportDestinationInProgress = nil
            endActivity()

            if review.hasMatches {
                pendingExportReview = review
                exportLogger.info(
                    "issue_export_review_ready",
                    "Similar issue review is ready for user confirmation.",
                    metadata: [
                        "destination": destination.rawValue,
                        "session_id": currentSession.id.uuidString
                    ]
                )
                setStatus(.success("Review the similar \(destination.rawValue) issues before export."))
            } else {
                await finalizeIssueExport(using: review)
            }
        } catch {
            exportDestinationInProgress = nil
            endActivity()
            presentError(error)
        }
    }

    func cancelPendingExportReview() {
        pendingExportReview = nil
    }

    func setExportReviewResolution(_ resolution: SimilarIssueResolution, for issueID: UUID) {
        guard var review = pendingExportReview,
              let itemIndex = review.items.firstIndex(where: { $0.issue.id == issueID }) else {
            return
        }

        review.items[itemIndex].setResolution(resolution)
        pendingExportReview = review
    }

    func selectExportReviewMatch(_ matchID: String, for issueID: UUID) {
        guard var review = pendingExportReview,
              let itemIndex = review.items.firstIndex(where: { $0.issue.id == issueID }) else {
            return
        }

        review.items[itemIndex].selectMatch(id: matchID)
        pendingExportReview = review
    }

    func confirmPendingExportReview() async {
        guard let pendingExportReview else {
            return
        }

        await finalizeIssueExport(using: pendingExportReview)
    }

    private func finalizeIssueExport(using review: IssueExportReview) async {
        guard let currentSession = sessionSnapshot(with: review.sessionID) else {
            presentError(AppError.exportFailure("This session is no longer available in the library."))
            pendingExportReview = nil
            return
        }

        do {
            let preparedIssues = try preparedIssuesForExport(from: review)
            let duplicateMatches = try duplicateMatchResults(from: review)

            pendingExportReview = nil
            let combinedResults: [ExportResult]

            if preparedIssues.isEmpty {
                combinedResults = duplicateMatches
            } else {
                exportDestinationInProgress = review.destination
                setStatus(.transcribing("Exporting reviewed issues to \(review.destination.rawValue)..."))
                beginActivity(reason: "Exporting extracted issues")

                let exportedResults: [ExportResult]
                switch review.destination {
                case .github:
                    guard let configuration = settingsStore.githubExportConfiguration else {
                        throw AppError.exportConfigurationMissing(
                            "GitHub export requires a token, repository owner, and repository name."
                        )
                    }
                    exportedResults = try await exportService.exportToGitHub(
                        issues: preparedIssues,
                        session: currentSession,
                        configuration: configuration
                    )
                case .jira:
                    guard let configuration = settingsStore.jiraExportConfiguration else {
                        throw AppError.exportConfigurationMissing(
                            "Jira export requires a base URL, email, API token, project key, and issue type."
                        )
                    }
                    exportedResults = try await exportService.exportToJira(
                        issues: preparedIssues,
                        session: currentSession,
                        configuration: configuration
                    )
                }

                combinedResults = exportedResults + duplicateMatches
                exportDestinationInProgress = nil
                endActivity()
            }

            exportLogger.info(
                "issue_export_completed",
                "Finished exporting selected issues.",
                metadata: [
                    "destination": review.destination.rawValue,
                    "session_id": currentSession.id.uuidString,
                    "issue_count": "\(combinedResults.count)"
                ]
            )
            setStatus(.success(exportSummary(for: combinedResults, duplicateCount: duplicateMatches.count, destination: review.destination)))
        } catch {
            exportDestinationInProgress = nil
            endActivity()
            presentError(error)
        }
    }

    private func preparedIssuesForExport(from review: IssueExportReview) throws -> [ExtractedIssue] {
        try review.items.compactMap { item in
            switch item.resolution {
            case .exportNew:
                return item.issue
            case .linkAsRelated:
                guard let match = item.selectedMatch else {
                    throw AppError.exportFailure("Choose a related \(review.destination.rawValue) issue before linking.")
                }

                var issue = item.issue
                issue.note = trackerContextNote(for: .linkAsRelated, match: match)
                return issue
            case .markDuplicate:
                return nil
            }
        }
    }

    private func duplicateMatchResults(from review: IssueExportReview) throws -> [ExportResult] {
        try review.items.compactMap { item in
            guard item.resolution == .markDuplicate else {
                return nil
            }

            guard let match = item.selectedMatch else {
                throw AppError.exportFailure("Choose an existing \(review.destination.rawValue) issue to mark as duplicate.")
            }

            return ExportResult(
                sourceIssueID: item.issue.id,
                destination: review.destination,
                remoteIdentifier: match.remoteIdentifier,
                remoteURL: match.remoteURL
            )
        }
    }

    private func trackerContextNote(for resolution: SimilarIssueResolution, match: SimilarIssueMatch) -> String {
        switch resolution {
        case .exportNew:
            return ""
        case .linkAsRelated:
            return "Related to \(match.remoteIdentifier) (\(match.confidenceLabel) match): \(match.title). \(match.reasoning)"
        case .markDuplicate:
            return "Marked as duplicate of \(match.remoteIdentifier) (\(match.confidenceLabel) match): \(match.title). \(match.reasoning)"
        }
    }

    private func exportSummary(
        for results: [ExportResult],
        duplicateCount: Int,
        destination: ExportDestination
    ) -> String {
        let createdCount = max(0, results.count - duplicateCount)

        if duplicateCount > 0, createdCount > 0 {
            return "Exported \(createdCount) new issue\(createdCount == 1 ? "" : "s") to \(destination.rawValue) and linked \(duplicateCount) to existing tracker items."
        }

        if duplicateCount > 0 {
            return "Linked \(duplicateCount) issue\(duplicateCount == 1 ? "" : "s") to existing \(destination.rawValue) items without creating duplicates."
        }

        return "Exported \(createdCount) issues to \(destination.rawValue)."
    }

    func openScreenshot(_ screenshot: SessionScreenshot) {
        guard FileManager.default.fileExists(atPath: screenshot.fileURL.path) else {
            presentUtilityActionFailure("The selected screenshot file is no longer available on this Mac.")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([screenshot.fileURL])
    }

    private func handleHotKeyPressed(_ action: HotkeyAction) {
        switch action {
        case .startRecording:
            Task {
                await openRecordingControlsAndStartSession()
            }
        case .stopRecording:
            guard status.phase == .recording else {
                return
            }
            Task {
                await stopSession()
            }
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }

    private func openExternalURL(_ url: URL, label: String) {
        guard urlHandler.open(url) else {
            presentUtilityActionFailure("BugNarrator could not open the \(label).")
            return
        }

        settingsLogger.info(
            "external_link_opened",
            "Opened an external support or documentation link.",
            metadata: ["label": label]
        )
    }

    private func presentUtilityActionFailure(_ message: String) {
        settingsLogger.warning("utility_action_failed", message)
        switch status.phase {
        case .recording:
            setStatus(.recording("\(message) Recording is still active."))
        case .transcribing:
            setStatus(.transcribing("\(message) Background work is still in progress."))
        case .idle, .success, .error:
            setStatus(.error(message))
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        let startDate = Date()

        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.elapsedDuration = Date().timeIntervalSince(startDate)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTimer(resetElapsed: Bool) {
        timerTask?.cancel()
        timerTask = nil

        if resetElapsed {
            elapsedDuration = 0
        }
    }

    private func beginActivity(reason: String) {
        endActivity()
        processActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
    }

    private func swapActivity(reason: String) {
        beginActivity(reason: reason)
    }

    private func endActivity() {
        if let processActivity {
            ProcessInfo.processInfo.endActivity(processActivity)
        }

        processActivity = nil
    }

    private func prepareForApplicationTermination() {
        settingsLogger.info(
            "application_will_terminate",
            "BugNarrator is preparing for application shutdown.",
            metadata: [
                "status_phase": status.phase.debugName,
                "has_active_recording_session": activeRecordingSession == nil ? "no" : "yes",
                "is_extracting_issues": issueExtractionSessionID == nil ? "no" : "yes",
                "is_exporting": exportDestinationInProgress == nil ? "no" : "yes"
            ]
        )

        if let activeRecordingSession {
            recordingLogger.warning(
                "application_terminating_during_recording",
                "BugNarrator is terminating while a recording session is still active.",
                metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
            )
        }

        toastDismissTask?.cancel()
        transientToast = nil
        hotkeyManager.unregisterAll()
        stopTimer(resetElapsed: false)
        endActivity()
    }

    private func setStatus(_ newStatus: AppStatus, error: AppError? = nil) {
        status = newStatus
        currentError = error
    }

    private func presentError(_ error: Error) {
        stopTimer(resetElapsed: status.phase == .recording)
        endActivity()
        cleanupPendingRecordedAudioIfNeeded()
        issueExtractionSessionID = nil
        exportDestinationInProgress = nil

        let appError = (error as? AppError) ?? .transcriptionFailure(error.localizedDescription)
        logAppError(appError, context: "present_error")
        setStatus(.error(appError.userMessage), error: appError)

        switch appError {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey, .exportConfigurationMissing:
            showSettingsWindow?()
        default:
            break
        }
    }

    private func presentPostTranscriptionError(_ error: Error) {
        let appError = (error as? AppError) ?? .issueExtractionFailure(error.localizedDescription)
        logAppError(appError, context: "present_post_transcription_error")
        setStatus(.error("Transcript ready, but \(appError.userMessage)"), error: appError)

        switch appError {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            showSettingsWindow?()
        default:
            break
        }
    }

    private func cleanupPendingRecordedAudioIfNeeded() {
        guard let pendingRecordedAudio else {
            return
        }

        if !settingsStore.debugMode {
            try? FileManager.default.removeItem(at: pendingRecordedAudio.fileURL)
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

    private func makeTranscriptionRequest() -> TranscriptionRequest {
        TranscriptionRequest(
            model: settingsStore.preferredModelValue,
            languageHint: settingsStore.normalizedLanguageHint,
            prompt: settingsStore.normalizedPrompt
        )
    }

    private func recoverablePendingTranscriptionReason(for error: Error) -> PendingTranscriptionFailureReason? {
        guard let appError = error as? AppError else {
            return nil
        }

        return PendingTranscriptionFailureReason(appError: appError)
    }

    private func preserveRetryableSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        failureReason: PendingTranscriptionFailureReason
    ) {
        let appError = failureReason.appError

        do {
            let preservedAudioURL = try preserveRecordedAudioForRetry(
                recordedAudio,
                in: recordingSession.artifactsDirectoryURL
            )

            let retryableSession = TranscriptSession(
                id: recordingSession.sessionID,
                createdAt: Date(),
                transcript: "",
                duration: recordedAudio.duration,
                model: request.model,
                languageHint: request.languageHint,
                prompt: request.prompt,
                markers: recordingSession.markers,
                screenshots: recordingSession.screenshots,
                sections: [],
                issueExtraction: nil,
                pendingTranscription: PendingTranscription(
                    audioFileName: preservedAudioURL.lastPathComponent,
                    failureReason: failureReason,
                    preservedAt: Date()
                ),
                updatedAt: Date(),
                artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
            )

            do {
                try transcriptStore.add(retryableSession)
            } catch {
                currentTranscript = retryableSession
                selectedTranscriptID = retryableSession.id
                activeRecordingSession = nil
                cleanupPendingRecordedAudioIfNeeded()
                endActivity()

                let persistenceError = (error as? AppError) ?? .storageFailure(error.localizedDescription)
                sessionLibraryLogger.error(
                    "retryable_session_persist_failed",
                    "The preserved recording could not be saved into local session history.",
                    metadata: ["session_id": retryableSession.id.uuidString]
                )
                setStatus(
                    .error("Recording preserved, but \(persistenceError.userMessage)"),
                    error: persistenceError
                )
                showTranscriptWindow?()
                if appError.suggestsOpenAISettings {
                    showSettingsWindow?()
                }
                return
            }

            currentTranscript = retryableSession
            selectedTranscriptID = retryableSession.id
            activeRecordingSession = nil
            cleanupPendingRecordedAudioIfNeeded()
            endActivity()
            transcriptionLogger.warning(
                "transcription_deferred_for_retry",
                "Recording finished and was preserved for a later transcription retry.",
                metadata: [
                    "session_id": retryableSession.id.uuidString,
                    "failure_reason": failureReason.rawValue
                ]
            )
            logAppError(appError, context: "preserve_retryable_session")
            setStatus(.error(retryableSession.transcriptionRecoveryMessage ?? appError.userMessage), error: appError)
            showTranscriptWindow?()
            if appError.suggestsOpenAISettings {
                showSettingsWindow?()
            }
        } catch {
            if !settingsStore.debugMode {
                artifactsService.removeArtifactsDirectory(at: recordingSession.artifactsDirectoryURL)
            }
            activeRecordingSession = nil
            presentError(error)
        }
    }

    private func preserveRecordedAudioForRetry(
        _ recordedAudio: RecordedAudio,
        in artifactsDirectoryURL: URL
    ) throws -> URL {
        let fileManager = FileManager.default
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

    private func cleanupPreservedRetryAudioIfNeeded(at audioFileURL: URL) {
        guard !settingsStore.debugMode else {
            recordingLogger.debug(
                "preserved_retry_audio_retained",
                "Kept the preserved retry audio because debug mode is enabled.",
                metadata: ["file_name": audioFileURL.lastPathComponent]
            )
            return
        }

        try? FileManager.default.removeItem(at: audioFileURL)
        recordingLogger.debug(
            "preserved_retry_audio_removed",
            "Removed the preserved retry audio after transcription succeeded.",
            metadata: ["file_name": audioFileURL.lastPathComponent]
        )
    }

    private func persistCompletedTranscript(_ session: TranscriptSession) throws {
        try transcriptStore.add(session)
        selectedTranscriptID = session.id

        if settingsStore.autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }

        sessionLibraryLogger.info(
            "transcript_persisted",
            "Persisted a completed transcript session.",
            metadata: [
                "session_id": session.id.uuidString,
                "auto_saved": "required",
                "auto_copied": settingsStore.autoCopyTranscript ? "yes" : "no"
            ]
        )
    }

    private func persistUpdatedSession(_ session: TranscriptSession) throws {
        var session = session
        session.updatedAt = Date()

        currentTranscript = session

        if transcriptStore.session(with: session.id) != nil {
            try transcriptStore.add(session)
        }

        selectedTranscriptID = session.id
        sessionLibraryLogger.debug(
            "session_updated",
            "Updated a transcript session in memory or local storage.",
            metadata: ["session_id": session.id.uuidString]
        )
    }

    private func preflightForSessionStart() async -> RecordingStartPreflightResult {
        await microphonePermissionService.preflightForRecordingStart(audioRecorder: audioRecorder)
    }

    private func preflightForIssueExtraction(_ session: TranscriptSession) -> AppError? {
        guard settingsStore.hasAPIKey else {
            return .missingAPIKey
        }

        let transcript = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return .emptyTranscript
        }

        guard status.phase != .recording else {
            return .recordingFailure("Stop the current recording before extracting issues.")
        }

        return nil
    }

    private func validateExportConfiguration(for destination: ExportDestination) throws {
        switch destination {
        case .github:
            guard settingsStore.githubExportConfiguration != nil else {
                throw AppError.exportConfigurationMissing(
                    "GitHub export requires a token, repository owner, and repository name."
                )
            }
        case .jira:
            guard settingsStore.jiraExportConfiguration != nil else {
                throw AppError.exportConfigurationMissing(
                    "Jira export requires a base URL, email, API token, project key, and issue type."
                )
            }
        }
    }

    private func editableSession(with sessionID: UUID) -> TranscriptSession? {
        sessionSnapshot(with: sessionID)
    }

    private func preferredTranscriptSelection() -> UUID? {
        if let currentTranscript, !currentTranscriptIsPersisted {
            return currentTranscript.id
        }

        return transcriptStore.sessions.first?.id
    }

    private func sessionSnapshot(with sessionID: UUID) -> TranscriptSession? {
        if currentTranscript?.id == sessionID {
            return currentTranscript
        }

        return transcriptStore.session(with: sessionID)
    }

    private func cleanupArtifactsForDeletedSession(_ session: TranscriptSession) {
        if let artifactsDirectoryURL = session.artifactsDirectoryURL {
            artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
            return
        }

        let directories = Set(
            session.screenshots.map { screenshot in
                screenshot.fileURL.deletingLastPathComponent()
            }
        )

        directories.forEach { directoryURL in
            artifactsService.removeArtifactsDirectory(at: directoryURL)
        }
    }

    private func performScreenshotCapture(
        in recordingSession: RecordingSessionDraft,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval,
        associatedMarkerID: UUID?
    ) async throws -> SessionScreenshot? {
        guard !isCapturingScreenshot else {
            throw AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
        }

        isCapturingScreenshot = true
        defer { isCapturingScreenshot = false }

        let preflightResult = await screenCapturePermissionService.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotCaptureService,
            hasActiveRecordingSession: true
        )
        if let preflightError = preflightResult.error {
            throw preflightError
        }

        prepareForScreenshotSelection?()
        defer {
            restoreAfterScreenshotSelection?()
        }

        let selectionResult = try await screenshotSelectionService.selectRegion()
        guard case let .selected(selectionRect) = selectionResult else {
            return nil
        }

        let screenshotURL = artifactsService.makeScreenshotURL(
            in: recordingSession.artifactsDirectoryURL,
            prefix: prefix,
            index: index,
            elapsedTime: elapsedTime
        )

        do {
            try await screenshotCaptureService.captureScreenshot(in: selectionRect, to: screenshotURL)
        } catch {
            try? FileManager.default.removeItem(at: screenshotURL)
            throw error
        }

        guard status.phase == .recording,
              activeRecordingSession?.sessionID == recordingSession.sessionID else {
            try? FileManager.default.removeItem(at: screenshotURL)
            throw AppError.screenshotCaptureFailure("The session ended before the screenshot finished saving.")
        }

        return SessionScreenshot(
            elapsedTime: elapsedTime,
            filePath: screenshotURL.path,
            associatedMarkerID: associatedMarkerID
        )
    }

    private func showToast(_ message: String, style: TransientToastStyle = .success) {
        toastDismissTask?.cancel()
        transientToast = TransientToast(message: message, style: style)
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.transientToast = nil
        }
    }

    private func logAppError(_ error: AppError, context: String) {
        let metadata = ["context": context]

        switch error {
        case .microphonePermissionDenied, .microphonePermissionRestricted, .microphoneUnavailable, .screenRecordingPermissionDenied:
            permissionsLogger.warning("app_error", error.userMessage, metadata: metadata)
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            settingsLogger.warning("app_error", error.userMessage, metadata: metadata)
        case .recordingFailure:
            recordingLogger.error("app_error", error.userMessage, metadata: metadata)
        case .transcriptionFailure, .openAIRequestRejected, .issueExtractionFailure, .emptyTranscript, .networkTimeout, .networkFailure:
            transcriptionLogger.error("app_error", error.userMessage, metadata: metadata)
        case .screenshotCaptureFailure:
            screenshotLogger.error("app_error", error.userMessage, metadata: metadata)
        case .exportConfigurationMissing, .exportFailure:
            exportLogger.error("app_error", error.userMessage, metadata: metadata)
        case .storageFailure:
            sessionLibraryLogger.error("app_error", error.userMessage, metadata: metadata)
        case .noActiveSession:
            recordingLogger.warning("app_error", error.userMessage, metadata: metadata)
        case .diagnosticsFailure:
            settingsLogger.error("app_error", error.userMessage, metadata: metadata)
        }
    }

    private var currentDebugSessionID: UUID? {
        activeRecordingSession?.sessionID ?? displayedTranscript?.id ?? currentTranscript?.id
    }

    private func currentDebugSessionMetadata() -> DebugSessionMetadata {
        DebugSessionMetadata.make(
            currentTranscript: currentTranscript,
            displayedTranscript: displayedTranscript,
            activeRecordingSession: activeRecordingSession,
            status: status,
            currentError: currentError
        )
    }

    private var microphoneRecoveryGuidanceDetails: MicrophoneRecoveryGuidance {
        microphonePermissionService.recoveryGuidance(
            for: microphoneRecoveryStatus,
            runtimeEnvironment: runtimeEnvironment
        )
    }

    private var microphoneRecoveryStatus: MicrophonePermissionStatus {
        switch currentError {
        case .microphonePermissionDenied:
            return .denied
        case .microphonePermissionRestricted:
            return .restricted
        case .microphoneUnavailable:
            return .captureSetupFailed
        default:
            return microphonePermissionService.currentStatus()
        }
    }

    private func makeDebugBundleSnapshot() async -> DebugBundleSnapshot {
        DebugBundleSnapshot(
            debugInfo: debugInfoSnapshot,
            sessionMetadata: currentDebugSessionMetadata(),
            recentLogText: await BugNarratorDiagnostics.recentLogText()
        )
    }

    private func validateRuntimeConfiguration() {
        guard let microphoneUsageDescription = Bundle.main.object(
            forInfoDictionaryKey: "NSMicrophoneUsageDescription"
        ) as? String else {
            permissionsLogger.error(
                "runtime_configuration_missing_microphone_usage_description",
                "BugNarrator is missing NSMicrophoneUsageDescription. macOS microphone prompting will not work correctly."
            )
            return
        }

        if microphoneUsageDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            permissionsLogger.error(
                "runtime_configuration_empty_microphone_usage_description",
                "BugNarrator has an empty NSMicrophoneUsageDescription. macOS microphone prompting will not work correctly."
            )
        }
    }

    private func logLaunchDiagnostics() {
        permissionsLogger.info(
            "launch_permission_snapshot",
            "Captured the initial permission state snapshot for this BugNarrator app copy.",
            metadata: [
                "bundle_path": runtimeEnvironment.bundlePath,
                "is_local_testing_build": runtimeEnvironment.isLocalTestingBuild ? "yes" : "no",
                "microphone_status": microphonePermissionService.currentStatus().rawValue,
                "screen_capture_status": screenCapturePermissionService.currentStatus().rawValue
            ]
        )

        sessionLibraryLogger.info(
            "launch_session_store_snapshot",
            "Captured the initial session library state at launch.",
            metadata: [
                "stored_session_count": "\(transcriptStore.sessions.count)",
                "selected_transcript_id": selectedTranscriptID?.uuidString ?? "none"
            ]
        )
    }

}

private extension AppStatus.Phase {
    var debugName: String {
        switch self {
        case .idle:
            return "idle"
        case .recording:
            return "recording"
        case .transcribing:
            return "transcribing"
        case .success:
            return "success"
        case .error:
            return "error"
        }
    }
}
