import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var status: AppStatus = .idle()
    @Published private(set) var currentError: AppError?
    @Published private(set) var elapsedDuration: TimeInterval = 0
    @Published var showDiscardConfirmation = false
    @Published var currentTranscript: TranscriptSession?
    @Published var selectedTranscriptID: UUID?
    @Published private(set) var activeRecordingSession: RecordingSessionDraft?
    @Published private(set) var issueExtractionSessionID: UUID?
    @Published private(set) var exportDestinationInProgress: ExportDestination?
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

    private let audioRecorder: any AudioRecording
    private let microphonePermissionService: any MicrophonePermissionServicing
    private let transcriptionClient: any TranscriptionServing
    private let hotkeyManager: any HotkeyManaging
    private let screenshotCaptureService: any ScreenshotCapturing
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

    init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        audioRecorder: AudioRecording = AudioRecorder(),
        microphonePermissionService: any MicrophonePermissionServicing = MicrophonePermissionService(),
        transcriptionClient: any TranscriptionServing = TranscriptionClient(),
        hotkeyManager: any HotkeyManaging = HotkeyManager(),
        screenshotCaptureService: any ScreenshotCapturing = ScreenshotCaptureService(),
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
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.screenshotCaptureService = screenshotCaptureService
        self.issueExtractionService = issueExtractionService
        self.exportService = exportService
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.urlHandler = urlHandler
        self.selectedTranscriptID = transcriptStore.sessions.first?.id

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

        settingsStore.$markerHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .insertMarker)
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

        hotkeyManager.register(shortcut: settingsStore.startRecordingHotkeyShortcut, for: .startRecording)
        hotkeyManager.register(shortcut: settingsStore.stopRecordingHotkeyShortcut, for: .stopRecording)
        hotkeyManager.register(shortcut: settingsStore.markerHotkeyShortcut, for: .insertMarker)
        hotkeyManager.register(shortcut: settingsStore.screenshotHotkeyShortcut, for: .captureScreenshot)

        settingsLogger.info(
            "app_state_initialized",
            "BugNarrator finished initializing application state.",
            metadata: [
                "has_openai_key": settingsStore.hasAPIKey ? "yes" : "no",
                "debug_mode": settingsStore.debugMode ? "enabled" : "disabled"
            ]
        )
    }

    var elapsedTimeString: String {
        ElapsedTimeFormatter.string(from: elapsedDuration)
    }

    var activeMarkerCount: Int {
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
        guard status.phase != .recording, status.phase != .transcribing else {
            return
        }

        guard currentError?.suggestsMicrophoneSettings == true else {
            return
        }

        guard microphonePermissionService.currentStatus() == .granted else {
            return
        }

        setStatus(.idle("Microphone access enabled. You can start a session again."))
    }

    func canExportIssues(from session: TranscriptSession, to destination: ExportDestination) -> Bool {
        guard status.phase != .recording,
              status.phase != .transcribing,
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

        do {
            recordingLogger.info(
                "session_stop_requested",
                "Stopping the active feedback session.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            let recordedAudio = try await audioRecorder.stopRecording()
            pendingRecordedAudio = recordedAudio

            guard settingsStore.hasAPIKey else {
                transcriptionLogger.warning(
                    "transcription_blocked_missing_key",
                    "Recording finished, but transcription could not start because the OpenAI API key is missing.",
                    metadata: ["session_id": recordingSession.sessionID.uuidString]
                )
                throw AppError.missingAPIKey
            }

            setStatus(.transcribing("Uploading audio to OpenAI and waiting for transcription..."))
            swapActivity(reason: "Uploading audio for transcription")

            let request = TranscriptionRequest(
                model: settingsStore.preferredModelValue,
                languageHint: settingsStore.normalizedLanguageHint,
                prompt: settingsStore.normalizedPrompt
            )

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
                setStatus(.transcribing("Extracting reviewable issues..."))
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
                    ? "Transcript and extracted issues are ready."
                    : (settingsStore.autoCopyTranscript
                        ? "Transcript copied to the clipboard."
                        : "Transcript ready.")
            ))
        } catch {
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
        settingsStore.refreshSecretsForUserInitiatedAccess()
        showSettingsWindow?()
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

        clipboardService.copy(transcript.transcript)
        setStatus(.success("Transcript copied to the clipboard."))
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

    func insertMarker(
        title: String? = nil,
        note: String? = nil,
        captureScreenshot: Bool = false
    ) async {
        guard status.phase == .recording, var recordingSession = activeRecordingSession else {
            let error = AppError.noActiveSession("Start a feedback session before inserting a marker.")
            recordingLogger.warning("marker_insert_rejected", error.userMessage)
            setStatus(.error(error.userMessage), error: error)
            return
        }

        if isCapturingScreenshot {
            let error = AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
            screenshotLogger.warning("marker_insert_rejected_during_capture", error.userMessage)
            setStatus(.recording(error.userMessage), error: error)
            return
        }

        let markerIndex = recordingSession.markers.count + 1
        let elapsedTime = max(audioRecorder.currentDuration, elapsedDuration)
        let markerTitle = normalizedMarkerTitle(title, index: markerIndex)
        let markerID = UUID()

        var screenshot: SessionScreenshot?
        var statusMessage = "Inserted \(markerTitle)."
        var warningError: AppError?

        if captureScreenshot {
            do {
                screenshot = try await performScreenshotCapture(
                    in: recordingSession,
                    prefix: "marker",
                    index: recordingSession.screenshots.count + 1,
                    elapsedTime: elapsedTime,
                    associatedMarkerID: markerID
                )
                guard status.phase == .recording,
                      var latestRecordingSession = activeRecordingSession,
                      latestRecordingSession.sessionID == recordingSession.sessionID else {
                    return
                }
                latestRecordingSession.screenshots.append(screenshot!)
                recordingSession = latestRecordingSession
                statusMessage = "Inserted \(markerTitle) with a screenshot."
            } catch {
                let appError = (error as? AppError) ?? .screenshotCaptureFailure(error.localizedDescription)
                guard status.phase == .recording else {
                    return
                }
                statusMessage = "\(markerTitle) was inserted, but the screenshot failed."
                warningError = appError
                screenshotLogger.warning(
                    "marker_screenshot_failed",
                    appError.userMessage,
                    metadata: ["session_id": recordingSession.sessionID.uuidString]
                )
            }
        }

        recordingSession.markers.append(
            SessionMarker(
                id: markerID,
                index: markerIndex,
                elapsedTime: elapsedTime,
                title: markerTitle,
                note: normalizeOptional(note),
                screenshotID: screenshot?.id
            )
        )

        activeRecordingSession = recordingSession
        recordingLogger.info(
            "marker_inserted",
            statusMessage,
            metadata: [
                "session_id": recordingSession.sessionID.uuidString,
                "marker_count": "\(recordingSession.markers.count)"
            ]
        )
        setStatus(.recording(statusMessage), error: warningError)
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
                    note: "Created automatically from a screenshot capture.",
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
            setStatus(.recording("Captured Screenshot \(screenshotIndex) and added \(markerTitle) marker."))
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

    func extractIssuesForDisplayedTranscript() async {
        guard let transcriptSession = displayedTranscript else {
            return
        }

        settingsStore.refreshOpenAISecretForUserInitiatedAccess()

        guard let preflightError = preflightForIssueExtraction(transcriptSession) else {
            issueExtractionSessionID = transcriptSession.id
            setStatus(.transcribing("Extracting reviewable issues..."))
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

        exportDestinationInProgress = destination
        setStatus(.transcribing("Exporting \(selectedIssues.count) issues to \(destination.rawValue)..."))
        beginActivity(reason: "Exporting extracted issues")
        exportLogger.info(
            "issue_export_requested",
            "Exporting selected issues.",
            metadata: [
                "destination": destination.rawValue,
                "session_id": currentSession.id.uuidString,
                "issue_count": "\(selectedIssues.count)"
            ]
        )

        do {
            let results: [ExportResult]

            switch destination {
            case .github:
                guard let configuration = settingsStore.githubExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "GitHub export requires a token, repository owner, and repository name."
                    )
                }
                results = try await exportService.exportToGitHub(
                    issues: selectedIssues,
                    session: currentSession,
                    configuration: configuration
                )
            case .jira:
                guard let configuration = settingsStore.jiraExportConfiguration else {
                    throw AppError.exportConfigurationMissing(
                        "Jira export requires a base URL, email, API token, project key, and issue type."
                    )
                }
                results = try await exportService.exportToJira(
                    issues: selectedIssues,
                    session: currentSession,
                    configuration: configuration
                )
            }

            exportDestinationInProgress = nil
            endActivity()
            exportLogger.info(
                "issue_export_completed",
                "Finished exporting selected issues.",
                metadata: [
                    "destination": destination.rawValue,
                    "session_id": currentSession.id.uuidString,
                    "issue_count": "\(results.count)"
                ]
            )
            setStatus(.success("Exported \(results.count) issues to \(destination.rawValue)."))
        } catch {
            exportDestinationInProgress = nil
            presentError(error)
        }
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
        case .insertMarker:
            Task {
                await insertMarker()
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

    private func persistCompletedTranscript(_ session: TranscriptSession) throws {
        if settingsStore.autoSaveTranscript {
            try transcriptStore.add(session)
            selectedTranscriptID = session.id
        } else {
            selectedTranscriptID = session.id
        }

        if settingsStore.autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }

        sessionLibraryLogger.info(
            "transcript_persisted",
            "Persisted a completed transcript session.",
            metadata: [
                "session_id": session.id.uuidString,
                "auto_saved": settingsStore.autoSaveTranscript ? "yes" : "no",
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
    ) async throws -> SessionScreenshot {
        guard !isCapturingScreenshot else {
            throw AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
        }

        isCapturingScreenshot = true
        defer { isCapturingScreenshot = false }

        let screenshotURL = artifactsService.makeScreenshotURL(
            in: recordingSession.artifactsDirectoryURL,
            prefix: prefix,
            index: index,
            elapsedTime: elapsedTime
        )

        do {
            try await screenshotCaptureService.captureScreenshot(to: screenshotURL)
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
            return .unavailable
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

    private func normalizedMarkerTitle(_ title: String?, index: Int) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? "Marker \(index)" : trimmedTitle
    }

    private func normalizeOptional(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

}
