import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var showDiscardConfirmation = false

    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let trackerIntegration: TrackerIntegrationController
    let aiProviderSettings: AIProviderSettingsController
    let recordingTimer: RecordingTimerViewModel
    let presentationState: AppPresentationState
    let errorPresenter: AppErrorPresenter
    let recordingSessionController: RecordingSessionController
    let sessionLibrary: SessionLibraryController
    let exportHistoryController: ExportHistoryController
    let recoveredRecordingImportController: RecoveredRecordingImportController
    let issueExtractionController: IssueExtractionController
    let issueExportController: IssueExportController
    let permissionRecoveryController: PermissionRecoveryController
    let appUtilityActions: AppUtilityActionController
    let supportDataController: SupportDataController
    let localDataDeletionController: LocalDataDeletionController
    let transcriptionRecovery: TranscriptionRecoveryController
    let screenshotCoordinator: ScreenshotCoordinator

    var showTranscriptWindow: (() -> Void)? { get { appUtilityActions.showTranscriptWindow } set { appUtilityActions.showTranscriptWindow = newValue } }
    var showSettingsWindow: (() -> Void)? { get { appUtilityActions.showSettingsWindow } set { appUtilityActions.showSettingsWindow = newValue } }
    var showAboutWindow: (() -> Void)? { get { appUtilityActions.showAboutWindow } set { appUtilityActions.showAboutWindow = newValue } }
    var showChangelogWindow: (() -> Void)? { get { appUtilityActions.showChangelogWindow } set { appUtilityActions.showChangelogWindow = newValue } }
    var showSupportWindow: (() -> Void)? { get { appUtilityActions.showSupportWindow } set { appUtilityActions.showSupportWindow = newValue } }
    var showRecordingControlWindow: (() -> Void)? { get { appUtilityActions.showRecordingControlWindow } set { appUtilityActions.showRecordingControlWindow = newValue } }

    var prepareForScreenshotSelection: (() -> Void)?
    var restoreAfterScreenshotSelection: (() -> Void)?

    private let transcriptionClient: any TranscriptionServing
    private let hotkeyManager: any HotkeyManaging
    private let artifactsService: any SessionArtifactsManaging
    private let clipboardService: any ClipboardWriting
    private let telemetryRecorder: any OperationalTelemetryRecording

    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let transcriptionLogger = DiagnosticsLogger(category: .transcription)
    private let sessionLibraryLogger = DiagnosticsLogger(category: .sessionLibrary)
    private let permissionsLogger = DiagnosticsLogger(category: .permissions)
    private let screenshotLogger = DiagnosticsLogger(category: .screenshots)
    private let settingsLogger = DiagnosticsLogger(category: .settings)

    private var cancellables = Set<AnyCancellable>()
    private var toastDismissTask: Task<Void, Never>?

    private enum PostTranscriptionPipelineMode: Equatable {
        case finishedRecording
        case retry

        var savingAction: String {
            switch self {
            case .finishedRecording:
                return "Saving the finished session locally..."
            case .retry:
                return "Saving the recovered session locally..."
            }
        }

        var recordsCompletionTelemetry: Bool {
            self == .finishedRecording
        }
    }

    private enum PostTranscriptionPipelineResult {
        case success(TranscriptSession)
        case persistenceFailure(session: TranscriptSession, error: Error)
        case postTranscriptionFailure(Error)
    }

    var status: AppStatus {
        presentationState.status
    }

    var currentError: AppError? {
        presentationState.currentError
    }

    var recoveredRecordingImportCount: Int {
        recoveredRecordingImportController.recoveredRecordingImportCount
    }

    var exportHistory: [ExportReceipt] {
        exportHistoryController.exportHistory
    }

    var exportDestinationInProgress: ExportDestination? {
        issueExportController.exportDestinationInProgress
    }

    var pendingExportReview: IssueExportReview? {
        issueExportController.pendingExportReview
    }

    var transientToast: TransientToast? {
        presentationState.transientToast
    }

    var currentTranscript: TranscriptSession? {
        get { sessionLibrary.currentTranscript }
        set { sessionLibrary.currentTranscript = newValue }
    }

    var selectedTranscriptID: UUID? {
        get { sessionLibrary.selectedTranscriptID }
        set { sessionLibrary.selectedTranscriptID = newValue }
    }

    var retryingSessionID: UUID? {
        transcriptionRecovery.retryingSessionID
    }

    var gitHubValidationState: APIKeyValidationState {
        trackerIntegration.gitHubValidationState
    }

    var jiraValidationState: APIKeyValidationState {
        trackerIntegration.jiraValidationState
    }

    var apiKeyValidationState: APIKeyValidationState {
        aiProviderSettings.apiKeyValidationState
    }

    var gitHubRepositories: [GitHubRepositoryOption] {
        trackerIntegration.gitHubRepositories
    }

    var isLoadingGitHubRepositories: Bool {
        trackerIntegration.isLoadingGitHubRepositories
    }

    var jiraProjects: [JiraProjectOption] {
        trackerIntegration.jiraProjects
    }

    var jiraIssueTypes: [JiraIssueTypeOption] {
        trackerIntegration.jiraIssueTypes
    }

    func jiraIssueTypes(for target: JiraIssueExportTarget) -> [JiraIssueTypeOption] {
        trackerIntegration.jiraIssueTypes(for: target)
    }

    var isLoadingJiraIssueTypes: Bool {
        trackerIntegration.isLoadingJiraIssueTypes
    }

    var jiraProjectMetadataIsStale: Bool {
        trackerIntegration.jiraProjectMetadataIsStale
    }

    var jiraIssueTypeMetadataIsStale: Bool {
        trackerIntegration.jiraIssueTypeMetadataIsStale
    }

    convenience init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment()
    ) {
        self.init(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            services: .production(settingsStore: settingsStore),
            runtimeEnvironment: runtimeEnvironment
        )
    }

    convenience init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        services: AppServiceContainer,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment()
    ) {
        self.init(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            audioRecorder: services.audioRecorder,
            microphonePermissionService: services.microphonePermissionService,
            screenCapturePermissionService: services.screenCapturePermissionService,
            transcriptionClient: services.transcriptionClient,
            hotkeyManager: services.hotkeyManager,
            screenshotCaptureService: services.screenshotCaptureService,
            screenshotSelectionService: services.screenshotSelectionService,
            issueExtractionService: services.issueExtractionService,
            exportService: services.exportService,
            recoveredRecordingImporter: services.recoveredRecordingImporter,
            artifactsService: services.artifactsService,
            clipboardService: services.clipboardService,
            urlHandler: services.urlHandler,
            debugBundleExporter: services.debugBundleExporter,
            privacyDataExporter: services.privacyDataExporter,
            telemetryRecorder: services.telemetryRecorder,
            localPrivacyDataManager: services.localPrivacyDataManager,
            recordingTimer: services.recordingTimer,
            runtimeEnvironment: runtimeEnvironment
        )
    }

    init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        audioRecorder: any AudioRecording,
        microphonePermissionService: any MicrophonePermissionServicing,
        screenCapturePermissionService: any ScreenCapturePermissionServicing,
        transcriptionClient: any TranscriptionServing,
        hotkeyManager: any HotkeyManaging,
        screenshotCaptureService: any ScreenshotCapturing,
        screenshotSelectionService: any ScreenshotSelecting,
        issueExtractionService: any IssueExtracting,
        exportService: any IssueExporting,
        recoveredRecordingImporter: any RecoveredRecordingImporting,
        artifactsService: any SessionArtifactsManaging,
        clipboardService: any ClipboardWriting,
        urlHandler: any URLOpening,
        debugBundleExporter: any DebugBundleExporting,
        privacyDataExporter: any PrivacyDataExporting,
        telemetryRecorder: any OperationalTelemetryRecording,
        localPrivacyDataManager: any LocalPrivacyDataManaging,
        recordingTimer: RecordingTimerViewModel,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment()
    ) {
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.recordingTimer = recordingTimer
        let presentationState = AppPresentationState()
        self.presentationState = presentationState
        self.errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
        self.recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: microphonePermissionService,
            artifactsService: artifactsService,
            recordingTimer: recordingTimer
        )
        self.sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: clipboardService
        )
        self.exportHistoryController = ExportHistoryController(exportService: exportService)
        self.recoveredRecordingImportController = RecoveredRecordingImportController(
            transcriptStore: transcriptStore,
            sessionLibrary: self.sessionLibrary,
            recoveredRecordingImporter: recoveredRecordingImporter,
            artifactsService: artifactsService
        )
        self.issueExtractionController = IssueExtractionController(
            sessionLibrary: self.sessionLibrary,
            issueExtractionService: issueExtractionService
        )
        self.issueExportController = IssueExportController(
            settingsStore: settingsStore,
            sessionLibrary: self.sessionLibrary,
            exportService: exportService
        )
        self.permissionRecoveryController = PermissionRecoveryController(
            microphonePermissionService: microphonePermissionService,
            screenCapturePermissionService: screenCapturePermissionService,
            urlHandler: urlHandler,
            runtimeEnvironment: runtimeEnvironment
        )
        self.appUtilityActions = AppUtilityActionController(
            urlHandler: urlHandler,
            permissionRecoveryController: self.permissionRecoveryController
        )
        self.supportDataController = SupportDataController(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            exportService: exportService,
            clipboardService: clipboardService,
            debugBundleExporter: debugBundleExporter,
            privacyDataExporter: privacyDataExporter,
            telemetryRecorder: telemetryRecorder,
            localPrivacyDataManager: localPrivacyDataManager
        )
        self.localDataDeletionController = LocalDataDeletionController(
            transcriptStore: transcriptStore,
            sessionLibrary: self.sessionLibrary,
            supportDataController: self.supportDataController,
            exportHistoryController: self.exportHistoryController
        )
        self.transcriptionRecovery = TranscriptionRecoveryController(
            sessionLibrary: self.sessionLibrary,
            artifactsService: artifactsService
        )
        self.screenshotCoordinator = ScreenshotCoordinator(
            screenCapturePermissionService: screenCapturePermissionService,
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: screenshotSelectionService,
            artifactsService: artifactsService
        )
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.telemetryRecorder = telemetryRecorder
        self.trackerIntegration = TrackerIntegrationController(
            settingsStore: settingsStore,
            exportService: exportService
        )
        self.aiProviderSettings = AIProviderSettingsController(
            settingsStore: settingsStore,
            transcriptionClient: transcriptionClient
        )

        BugNarratorDiagnostics.setDebugModeEnabled(settingsStore.debugMode)

        self.hotkeyManager.onHotKeyPressed = { [weak self] action in
            Task { @MainActor [weak self] in
                self?.handleHotKeyPressed(action)
            }
        }

        trackerIntegration.showSettingsWindow = { [weak self] in
            self?.showSettingsWindow?()
        }

        aiProviderSettings.showSettingsWindow = { [weak self] in
            self?.showSettingsWindow?()
        }

        trackerIntegration.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        aiProviderSettings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        presentationState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        recordingSessionController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        sessionLibrary.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        exportHistoryController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        recoveredRecordingImportController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        issueExtractionController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        issueExportController.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        transcriptionRecovery.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        screenshotCoordinator.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

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
                "ai_provider": settingsStore.aiProvider.rawValue,
                "audio_source": settingsStore.recordingAudioSource.diagnosticsValue,
                "debug_mode": settingsStore.debugMode ? "enabled" : "disabled"
            ]
        )
        validateRuntimeConfiguration()
        importRecoveredRecordingsAtLaunch()
        Task { [weak self] in
            await self?.refreshExportHistory()
        }
        logLaunchDiagnostics()
    }

    var elapsedTimeString: String {
        recordingTimer.elapsedTimeString
    }

    var elapsedDuration: TimeInterval {
        recordingTimer.elapsedDuration
    }

    var activeTimelineMomentCount: Int {
        activeRecordingSession?.markers.count ?? 0
    }

    var activeScreenshotCount: Int {
        activeRecordingSession?.screenshots.count ?? 0
    }

    func isActiveRecordingSession(_ sessionID: UUID) -> Bool {
        status.phase == .recording && activeRecordingSession?.sessionID == sessionID
    }

    var displayedTranscript: TranscriptSession? {
        sessionLibrary.displayedTranscript
    }

    var currentTranscriptIsPersisted: Bool {
        sessionLibrary.currentTranscriptIsPersisted
    }

    var needsAPIKeySetup: Bool {
        !settingsStore.hasUsableAIProviderCredential || settingsStore.aiProviderCompatibilityIssue != nil
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
        supportDataController.debugInfoSnapshot(sessionID: currentDebugSessionID)
    }

    var storageRecoveryMessage: String? {
        transcriptStore.lastLoadRecoveryEvent?.userMessage
    }

    var hasRecoveredRecordingPendingTranscription: Bool {
        transcriptStore.pendingTranscriptionSessions.contains {
            $0.pendingTranscription?.failureReason == .crashRecovery
        }
    }

    var activeRecordingSession: RecordingSessionDraft? {
        recordingSessionController.activeRecordingSession
    }

    var isScreenshotCaptureInProgress: Bool {
        screenshotCoordinator.isCaptureInProgress
    }

    func isExtractingIssues(for session: TranscriptSession) -> Bool {
        issueExtractionController.isExtractingIssues(for: session)
    }

    func isExporting(to destination: ExportDestination) -> Bool {
        issueExportController.isExporting(to: destination)
    }

    func refreshPermissionRecoveryState() {
        switch permissionRecoveryController.refreshRecoveryState(
            currentError: currentError,
            statusPhase: status.phase
        ) {
        case .unchanged:
            break
        case .recovered(let recoveredStatus):
            setStatus(recoveredStatus)
        }
    }

    func canExportIssues(from session: TranscriptSession, to destination: ExportDestination) -> Bool {
        issueExportController.canExportIssues(from: session, to: destination, statusPhase: status.phase)
    }

    func canRequestIssueExport(from session: TranscriptSession) -> Bool {
        issueExportController.canRequestIssueExport(from: session, statusPhase: status.phase)
    }

    func issueExportSetupMessage(for destination: ExportDestination) -> String? {
        issueExportController.issueExportSetupMessage(for: destination)
    }

    func issueExportRoutingMessage(for destination: ExportDestination, session: TranscriptSession) -> String? {
        issueExportController.issueExportRoutingMessage(for: destination, session: session)
    }

    func defaultGitHubIssueExportTarget() -> GitHubIssueExportTarget? {
        issueExportController.defaultGitHubIssueExportTarget()
    }

    func defaultJiraIssueExportTarget() -> JiraIssueExportTarget? {
        issueExportController.defaultJiraIssueExportTarget()
    }

    func startSession() async {
        recordingLogger.info(.sessionStartRequested, "A feedback session start was requested.")

        let outcome = await recordingSessionController.startSession(
            statusPhase: status.phase,
            activityReason: recordingActivityReason()
        )

        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStartIgnored, "The start request was ignored because another recording transition is already in progress.")
            return

        case .busy:
            recordingLogger.warning(.sessionStartRejected, "The start request was rejected because BugNarrator is already busy.")
            return

        case .restored(let recordingSession):
            recordingLogger.warning(
                "session_start_reconciled_active_session",
                "A start request arrived while a recording session draft was still active; restoring recording state instead of starting a duplicate recorder.",
                metadata: ["session_id": recordingSession.sessionID.uuidString]
            )
            setStatus(.recording(recordingDetailMessage()))
            return

        case .preflightFailure(let preflightError):
            permissionsLogger.warning(.sessionStartPreflightFailed, preflightError.userMessage)
            presentError(preflightError, operation: .recordingStart)
            return

        case .failure(let error):
            presentError(error, operation: .recordingStart, fallback: { .recordingFailure($0) })

        case .started(let recordingSession):
            setStatus(.recording(recordingDetailMessage()))
            recordingLogger.info(
                .sessionStarted,
                "A feedback session started successfully.",
                metadata: [
                    "session_id": recordingSession.sessionID.uuidString,
                    "audio_source": settingsStore.recordingAudioSource.diagnosticsValue,
                    "has_ai_provider_credential": settingsStore.hasUsableAIProviderCredential ? "yes" : "no",
                    "ai_provider": settingsStore.aiProvider.rawValue
                ]
            )
            telemetryRecorder.record(
                .recordingStarted,
                metadata: [
                    "audio_source": settingsStore.recordingAudioSource.diagnosticsValue,
                    "has_ai_provider_credential": settingsStore.hasUsableAIProviderCredential ? "yes" : "no",
                    "ai_provider": settingsStore.aiProvider.rawValue
                ]
            )
        }
    }

    private func recordingDetailMessage() -> String {
        let prefix: String
        switch settingsStore.recordingAudioSource {
        case .microphone:
            prefix = "Recording in progress."
        case .systemAudio:
            prefix = "Recording system audio."
        case .microphoneAndSystemAudio:
            prefix = "Recording microphone and system audio."
        }

        if settingsStore.hasUsableAIProviderCredential && settingsStore.aiProviderCompatibilityIssue == nil {
            return prefix
        }

        if let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
            return "\(prefix) \(compatibilityIssue)"
        }

        return "\(prefix) Finish the AI provider setup in Settings before stopping to transcribe this session."
    }

    private func recordingActivityReason() -> String {
        switch settingsStore.recordingAudioSource {
        case .microphone:
            return "Recording a spoken feedback session"
        case .systemAudio:
            return "Recording system audio for a feedback session"
        case .microphoneAndSystemAudio:
            return "Recording microphone and system audio for a feedback session"
        }
    }

    func stopSession() async {
        guard let recordingSession = beginStoppingSession() else {
            return
        }

        defer { recordingSessionController.finishStoppingSession() }

        cancelPendingScreenshotSelection(reason: "Stopping the active session cancels pending screenshot selection.")
        recordingSessionController.prepareForStopSession()
        let request = makeTranscriptionRequest()

        do {
            logSessionStopRequested(recordingSession)
            let recordedAudio = try await recordingSessionController.stopRecording()

            guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
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

            let transcriptionResult = try await transcribeAudio(
                at: recordedAudio.fileURL,
                request: request,
                apiKey: apiKey
            )
            let session = makeTranscriptSession(
                from: recordingSession,
                recordedAudio: recordedAudio,
                request: request,
                result: transcriptionResult
            )
            let result = await completePostTranscriptionPipeline(
                session: session,
                apiKey: apiKey,
                mode: .finishedRecording
            )
            handleFinishedRecordingPostTranscriptionResult(result)
        } catch {
            handleStopSessionFailure(error, recordingSession: recordingSession, request: request)
        }
    }

    func requestSessionCancel() {
        guard status.phase == .recording else {
            return
        }

        showDiscardConfirmation = true
    }

    func cancelSession() async {
        let outcome = await recordingSessionController.cancelSession(
            preserveFile: settingsStore.debugMode,
            onCancelWillBegin: { [weak self] in
                self?.showDiscardConfirmation = false
                self?.cancelPendingScreenshotSelection(reason: "Discarding the active session cancels pending screenshot selection.")
            }
        )

        switch outcome {
        case .transitionInProgress:
            recordingLogger.debug("session_cancel_ignored", "The cancel request was ignored because another recording transition is already in progress.")
            return

        case .cancelled(let activeRecordingSession):
            if let activeRecordingSession {
                recordingLogger.info(
                    "session_cancelled",
                    "The active feedback session was discarded.",
                    metadata: ["session_id": activeRecordingSession.sessionID.uuidString]
                )
            }
            setStatus(.idle("Session discarded."))
        }
    }

    func openTranscriptHistory() {
        appUtilityActions.openTranscriptHistory()
    }

    func openRecordingControls() {
        appUtilityActions.openRecordingControls()
    }

    func openRecordingControlsAndStartSession() async {
        appUtilityActions.openRecordingControls()

        guard status.phase != .recording else {
            return
        }

        await startSession()
    }

    func openSettings() {
        appUtilityActions.openSettings()
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
        cancelPendingScreenshotSelection(reason: "Quit was requested while recording, so pending screenshot selection was cancelled.")
        showRecordingControlWindow?()
        showToast("Stop recording before quitting BugNarrator.", style: .informational)
        return .terminateCancel
    }

    func openAbout() {
        appUtilityActions.openAbout()
    }

    func openChangelog() {
        appUtilityActions.openChangelog()
    }

    func openGitHubRepository() {
        presentUtilityActionResult(appUtilityActions.openGitHubRepository())
    }

    func openDocumentation() {
        presentUtilityActionResult(appUtilityActions.openDocumentation())
    }

    func openIssueReporter() {
        presentUtilityActionResult(appUtilityActions.openIssueReporter())
    }

    func openSupportDevelopment() {
        appUtilityActions.openSupportDevelopment()
    }

    func openSupportDonationPage() {
        presentUtilityActionResult(appUtilityActions.openSupportDonationPage())
    }

    func openMicrophonePrivacySettings() {
        presentPermissionSettingsResult(appUtilityActions.openMicrophonePrivacySettings())
    }

    func openScreenRecordingPrivacySettings() {
        presentPermissionSettingsResult(appUtilityActions.openScreenRecordingPrivacySettings())
    }

    func openSystemAudioPrivacySettings() {
        presentPermissionSettingsResult(appUtilityActions.openSystemAudioPrivacySettings())
    }

    func checkForUpdates() {
        presentUtilityActionResult(appUtilityActions.checkForUpdates())
    }

    func copyDebugInfo() {
        let result = supportDataController.copyDebugInfo(sessionID: currentDebugSessionID)
        setStatus(.success(result.statusMessage))
    }

    func exportDebugBundle() async {
        do {
            guard let completion = try await supportDataController.exportDebugBundle(
                sessionMetadata: currentDebugSessionMetadata()
            ) else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([completion.bundleURL])
            setStatus(.success(completion.statusMessage))
        } catch {
            presentError(
                error,
                operation: .diagnosticsExport,
                fallback: { _ in .diagnosticsFailure("BugNarrator could not create the debug bundle.") }
            )
        }
    }

    func exportPrivacyData() async {
        do {
            guard let completion = try await supportDataController.exportPrivacyData(
                exportHistoryFallback: exportHistory
            ) else {
                return
            }

            NSWorkspace.shared.activateFileViewerSelecting([completion.bundleURL])
            setStatus(.success(completion.statusMessage))
        } catch {
            presentError(
                error,
                operation: .privacyExport,
                fallback: { _ in .exportFailure("BugNarrator could not create the data export.") }
            )
        }
    }

    func deleteAllLocalData() async {
        guard status.phase != .recording, status.phase != .transcribing else {
            setStatus(.error("Stop recording or transcription before deleting local data."))
            return
        }

        do {
            let outcome = try await localDataDeletionController.deleteAllLocalData(currentTranscript: currentTranscript)
            setStatus(.success(outcome.statusMessage))
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func validateAPIKey() async {
        await aiProviderSettings.validateConnection()
    }

    func removeAPIKey() {
        aiProviderSettings.removeCredential()
    }

    func validateGitHubConfiguration() async {
        await trackerIntegration.validateGitHubConfiguration()
    }

    func loadGitHubRepositories() async {
        await trackerIntegration.loadGitHubRepositories()
    }

    func validateJiraConfiguration() async {
        await trackerIntegration.validateJiraConfiguration()
    }

    func selectJiraProject(projectID: String) {
        trackerIntegration.selectJiraProject(projectID: projectID)
    }

    func refreshJiraIssueTypesForSelectedProject() async {
        await trackerIntegration.refreshJiraIssueTypesForSelectedProject()
    }

    func loadJiraIssueTypes(forProjectID projectID: String) async {
        await trackerIntegration.loadJiraIssueTypes(forProjectID: projectID)
    }

    func refreshExportHistory() async {
        await exportHistoryController.refreshExportHistory()
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
        let retryContext: PendingTranscriptionRetryContext
        switch transcriptionRecovery.retryContext(
            for: sessionID,
            isRecording: status.phase == .recording,
            hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
            aiProviderCompatibilityIssue: settingsStore.aiProviderCompatibilityIssue
        ) {
        case .ready(let context):
            retryContext = context
        case .duplicate:
            return
        case .failure(let appError, let opensSettings, let statusMessage):
            if let statusMessage {
                setStatus(.error(statusMessage), error: appError)
            } else {
                presentError(appError, operation: .retryTranscription)
            }
            if opensSettings {
                showSettingsWindow?()
            }
            return
        }

        guard transcriptionRecovery.beginRetry(for: sessionID) else {
            return
        }

        let request = makeTranscriptionRequest()
        sessionLibrary.stageCurrentTranscript(retryContext.session)
        setStatus(.transcribing(transcriptionProgressMessage(step: 1, action: "Retrying transcription from the preserved recording...")))
        swapActivity(reason: "Retrying transcription from preserved audio")
        logPendingTranscriptionRetryRequested(retryContext)

        do {
            guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
                throw AppError.missingAPIKey
            }

            let result = try await transcribeAudio(
                at: retryContext.audioFileURL,
                request: request,
                apiKey: apiKey
            )
            let updatedSession = makeRecoveredTranscriptSession(
                from: retryContext.session,
                request: request,
                result: result
            )

            switch await completePostTranscriptionPipeline(
                session: updatedSession,
                apiKey: apiKey,
                mode: .retry
            ) {
            case .success:
                transcriptionRecovery.cleanupPreservedRetryAudioIfNeeded(
                    at: retryContext.audioFileURL,
                    debugMode: settingsStore.debugMode
                )
                transcriptionRecovery.finishRetry()
                finishSuccessfulTranscription(showTranscriptWindow: true)
            case .persistenceFailure(_, let error):
                transcriptionRecovery.finishRetry()
                presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
            case .postTranscriptionFailure(let error):
                transcriptionRecovery.cleanupPreservedRetryAudioIfNeeded(
                    at: retryContext.audioFileURL,
                    debugMode: settingsStore.debugMode
                )
                transcriptionRecovery.finishRetry()
                endActivity()
                presentPostTranscriptionError(error, operation: .retryTranscription)
            }
        } catch {
            if handlePendingTranscriptionRetryFailure(error, context: retryContext) {
                return
            }

            transcriptionRecovery.finishRetry()
            presentError(error, operation: .retryTranscription)
        }
    }

    func saveCurrentTranscriptToHistory() {
        do {
            if try sessionLibrary.saveCurrentTranscriptToHistory() != nil {
                setStatus(.success("Transcript saved to session history."))
            }
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func deleteDisplayedTranscript() {
        do {
            presentDeletedSessionStatus(try sessionLibrary.deleteDisplayedTranscript())
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        do {
            presentDeletedSessionStatus(try sessionLibrary.deleteSessions(withIDs: ids))
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    private func presentDeletedSessionStatus(_ deletedCount: Int) {
        if deletedCount > 0 {
            setStatus(.success(deletedCount == 1 ? "Deleted 1 session." : "Deleted \(deletedCount) sessions."))
        }
    }

    func captureScreenshot() async {
        guard status.phase == .recording, let recordingSession = activeRecordingSession else {
            let error = AppError.noActiveSession("Start a feedback session before capturing a screenshot.")
            screenshotLogger.warning("screenshot_rejected_no_session", error.userMessage)
            setStatus(.error(error.userMessage), error: error)
            return
        }

        if isScreenshotCaptureInProgress {
            let error = AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
            screenshotLogger.warning("screenshot_rejected_busy", error.userMessage)
            setStatus(.recording(error.userMessage), error: error)
            return
        }

        let screenshotIndex = recordingSession.screenshots.count + 1
        let markerIndex = recordingSession.markers.count + 1
        let elapsedTime = max(recordingSessionController.currentDuration, elapsedDuration)
        let markerID = UUID()
        let markerTitle = "Screenshot \(screenshotIndex)"

        do {
            let captureResult = try await screenshotCoordinator.captureScreenshot(
                in: recordingSession,
                prefix: "capture",
                index: screenshotIndex,
                elapsedTime: elapsedTime,
                associatedMarkerID: markerID,
                onSelectionWillBegin: { [weak self] in
                    self?.setStatus(.recording("Drag to select a screenshot region. Press Esc to cancel."))
                    self?.prepareForScreenshotSelection?()
                },
                onSelectionDidEnd: { [weak self] in
                    self?.restoreAfterScreenshotSelection?()
                },
                isSessionActive: { [weak self] sessionID in
                    guard let self else {
                        return false
                    }
                    return status.phase == .recording && activeRecordingSession?.sessionID == sessionID
                }
            )
            guard case let .captured(screenshot) = captureResult else {
                guard status.phase == .recording,
                      activeRecordingSession?.sessionID == recordingSession.sessionID else {
                    return
                }
                setStatus(.recording(recordingDetailMessage()))
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
            recordingSessionController.updateActiveRecordingSession(latestRecordingSession)
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
            let normalizedError = errorPresenter.normalizeError(
                error,
                operation: .screenshotCapture,
                fallback: { .screenshotCaptureFailure($0) }
            )
            let appError = normalizedError.appError
            guard status.phase == .recording else {
                return
            }
            errorPresenter.logAppError(normalizedError, context: "screenshot_capture_failed")
            var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "screenshot_capture_failed")
            metadata["session_id"] = recordingSession.sessionID.uuidString
            screenshotLogger.error(
                "screenshot_capture_failed",
                appError.userMessage,
                metadata: metadata
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

        guard let preflightError = issueExtractionController.preflightIssueExtraction(
            for: transcriptSession,
            hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
            aiProviderCompatibilityIssue: settingsStore.aiProviderCompatibilityIssue,
            statusPhase: status.phase
        ) else {
            setStatus(.transcribing("Running issue extraction with a 10-second time limit..."))
            beginActivity(reason: "Extracting review issues")
            transcriptionLogger.info(
                "issue_extraction_requested",
                "Issue extraction was requested for the selected transcript.",
                metadata: ["session_id": transcriptSession.id.uuidString]
            )

            do {
                guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
                    throw AppError.missingAPIKey
                }

                let extraction = try await issueExtractionController.extractIssues(
                    for: transcriptSession,
                    apiKey: apiKey,
                    model: settingsStore.issueExtractionModelValue,
                    apiBaseURL: settingsStore.openAIBaseURLValue,
                    completionLog: .manual
                )

                endActivity()
                setStatus(.success("Extracted \(extraction.issues.count) review issues."))
                showTranscriptWindow?()
            } catch {
                presentError(error, operation: .postTranscription, fallback: { .issueExtractionFailure($0) })
            }

            return
        }

        transcriptionLogger.warning(
            "issue_extraction_preflight_failed",
            preflightError.userMessage,
            metadata: ["session_id": transcriptSession.id.uuidString]
        )
        presentError(preflightError, operation: .postTranscription)
    }

    func updateExtractedIssue(_ updatedIssue: ExtractedIssue, in sessionID: UUID) {
        do {
            try issueExtractionController.updateExtractedIssue(updatedIssue, in: sessionID)
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func setIssueSelection(_ isSelected: Bool, issueID: UUID, in sessionID: UUID) {
        do {
            try issueExtractionController.setIssueSelection(isSelected, issueID: issueID, in: sessionID)
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func setAllIssuesSelected(_ isSelected: Bool, in sessionID: UUID) {
        do {
            try issueExtractionController.setAllIssuesSelected(isSelected, in: sessionID)
        } catch {
            presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
        }
    }

    func exportSelectedIssues(from session: TranscriptSession, to destination: ExportDestination) async {
        let context: IssueExportRequestContext
        switch issueExportController.preflightIssueExport(
            from: session,
            to: destination,
            statusPhase: status.phase
        ) {
        case .success(let readyContext):
            context = readyContext
        case .failure(let failure):
            presentError(failure.error, operation: .export, fallback: { .exportFailure($0) })
            if failure.opensSettings {
                showSettingsWindow?()
            }
            return
        }

        setStatus(.transcribing("Checking \(destination.rawValue) for similar open issues..."))
        beginActivity(reason: "Reviewing similar issues before export")

        do {
            let review = try await issueExportController.prepareIssueExportReview(
                for: context,
                model: settingsStore.issueExtractionModelValue,
                apiBaseURL: settingsStore.openAIBaseURLValue
            )
            endActivity()

            if review.hasMatches {
                setStatus(.success("Review the similar \(destination.rawValue) issues before export."))
            } else {
                await finalizeIssueExport(using: review)
            }
        } catch {
            endActivity()
            presentError(error, operation: .export, fallback: { .exportFailure($0) })
        }
    }

    func cancelPendingExportReview() {
        issueExportController.cancelPendingExportReview()
    }

    func setExportReviewResolution(_ resolution: SimilarIssueResolution, for issueID: UUID) {
        issueExportController.setExportReviewResolution(resolution, for: issueID)
    }

    func selectExportReviewMatch(_ matchID: String, for issueID: UUID) {
        issueExportController.selectExportReviewMatch(matchID, for: issueID)
    }

    func confirmPendingExportReview() async {
        guard let pendingExportReview else {
            return
        }

        await finalizeIssueExport(using: pendingExportReview)
    }

    private func finalizeIssueExport(using review: IssueExportReview) async {
        do {
            let requiresRemoteExport = try issueExportController.pendingReviewRequiresRemoteExport(review)
            if requiresRemoteExport {
                setStatus(.transcribing("Exporting reviewed issues to \(review.destination.rawValue)..."))
                beginActivity(reason: "Exporting extracted issues")
            }

            let completion = try await issueExportController.finalizeIssueExport(using: review)
            if completion.performedRemoteExport {
                endActivity()
            }

            setStatus(.success(completion.summary))
            await refreshExportHistory()
        } catch {
            endActivity()
            presentError(error, operation: .export, fallback: { .exportFailure($0) })
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
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }

    private func presentUtilityActionResult(_ result: AppUtilityActionResult) {
        guard case .failed(let message) = result else {
            return
        }

        presentUtilityActionFailure(message)
    }

    private func presentPermissionSettingsResult(_ result: PermissionSettingsOpenResult) {
        switch result {
        case .opened:
            return
        case .failed(let message):
            presentUtilityActionFailure(message)
        }
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
        recordingSessionController.startTimer()
    }

    private func stopTimer(resetElapsed: Bool) {
        recordingSessionController.stopTimer(resetElapsed: resetElapsed)
    }

    private func beginActivity(reason: String) {
        recordingSessionController.beginActivity(reason: reason)
    }

    private func swapActivity(reason: String) {
        recordingSessionController.swapActivity(reason: reason)
    }

    private func endActivity() {
        recordingSessionController.endActivity()
    }

    private func prepareForApplicationTermination() {
        settingsLogger.info(
            "application_will_terminate",
            "BugNarrator is preparing for application shutdown.",
            metadata: [
                "status_phase": status.phase.debugName,
                "has_active_recording_session": activeRecordingSession == nil ? "no" : "yes",
                "is_extracting_issues": issueExtractionController.issueExtractionSessionID == nil ? "no" : "yes",
                "is_exporting": issueExportController.exportDestinationInProgress == nil ? "no" : "yes"
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
        presentationState.dismissToast()
        hotkeyManager.unregisterAll()
        stopTimer(resetElapsed: false)
        endActivity()
    }

    private func setStatus(_ newStatus: AppStatus, error: AppError? = nil) {
        errorPresenter.setStatus(newStatus, error: error)
    }

    private func presentError(
        _ error: Error,
        operation: AppErrorOperation = .generic,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        stopTimer(resetElapsed: status.phase == .recording)
        endActivity()
        cleanupPendingRecordedAudioIfNeeded()
        issueExtractionController.clearProgress()
        issueExportController.clearProgress()

        let result = errorPresenter.presentError(error, operation: operation, fallback: fallback)

        if result.shouldOpenSettingsWindow {
            showSettingsWindow?()
        }
    }

    private func presentPostTranscriptionError(
        _ error: Error,
        operation: AppErrorOperation = .postTranscription
    ) {
        let result = errorPresenter.presentPostTranscriptionError(error, operation: operation)

        if result.shouldOpenSettingsWindow {
            showSettingsWindow?()
        }
    }

    private func cleanupPendingRecordedAudioIfNeeded() {
        recordingSessionController.cleanupPendingRecordedAudioIfNeeded(debugMode: settingsStore.debugMode)
    }

    private func makeTranscriptionRequest() -> TranscriptionRequest {
        TranscriptionRequest(
            model: settingsStore.preferredModelValue,
            languageHint: settingsStore.normalizedLanguageHint,
            prompt: settingsStore.normalizedPrompt,
            apiBaseURL: settingsStore.openAIBaseURLValue
        )
    }

    private func logSessionStopRequested(_ recordingSession: RecordingSessionDraft) {
        recordingLogger.info(
            .sessionStopRequested,
            "Stopping the active feedback session.",
            metadata: ["session_id": recordingSession.sessionID.uuidString]
        )
    }

    private func beginStoppingSession() -> RecordingSessionDraft? {
        switch recordingSessionController.beginStoppingSession(statusPhase: status.phase) {
        case .transitionInProgress:
            recordingLogger.debug(.sessionStopIgnored, "The stop request was ignored because another recording transition is already in progress.")
            return nil

        case .noActiveRecording:
            recordingLogger.warning(.sessionStopRejected, "The stop request was rejected because no recording session is active.")
            return nil

        case .missingSessionMetadata:
            presentError(
                AppError.recordingFailure("The recording session metadata was unavailable."),
                operation: .recordingStop
            )
            return nil

        case .ready(let recordingSession):
            return recordingSession
        }
    }

    private func transcribeAudio(
        at fileURL: URL,
        request: TranscriptionRequest,
        apiKey: String
    ) async throws -> TranscriptionResult {
        try await transcriptionClient.transcribe(fileURL: fileURL, apiKey: apiKey, request: request)
    }

    private func makeTranscriptSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        result: TranscriptionResult
    ) -> TranscriptSession {
        let sections = TranscriptSectionBuilder.buildSections(
            transcript: result.text,
            segments: result.segments,
            markers: recordingSession.markers,
            duration: recordedAudio.duration
        )

        return TranscriptSession(
            id: recordingSession.sessionID,
            createdAt: Date(),
            transcript: result.text,
            duration: recordedAudio.duration,
            model: request.model,
            languageHint: request.languageHint,
            prompt: request.prompt,
            markers: recordingSession.markers,
            screenshots: recordingSession.screenshots,
            sections: sections,
            transcriptQualityFindings: result.qualityFindings,
            artifactsDirectoryPath: recordingSession.artifactsDirectoryURL.path
        )
    }

    private func makeRecoveredTranscriptSession(
        from session: TranscriptSession,
        request: TranscriptionRequest,
        result: TranscriptionResult
    ) -> TranscriptSession {
        let sections = TranscriptSectionBuilder.buildSections(
            transcript: result.text,
            segments: result.segments,
            markers: session.markers,
            duration: session.duration
        )

        return TranscriptSession(
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
            transcriptQualityFindings: result.qualityFindings,
            updatedAt: Date(),
            artifactsDirectoryPath: session.artifactsDirectoryPath
        )
    }

    private func completePostTranscriptionPipeline(
        session: TranscriptSession,
        apiKey: String,
        mode: PostTranscriptionPipelineMode
    ) async -> PostTranscriptionPipelineResult {
        var session = session
        recordCompletedTranscriptionIfNeeded(session, mode: mode)
        setStatus(.transcribing(transcriptionProgressMessage(step: 2, action: mode.savingAction)))

        do {
            try persistInitialPostTranscriptionSession(session, mode: mode)
        } catch {
            return .persistenceFailure(session: session, error: error)
        }

        finalizeInitialPostTranscriptionPersistence(session, mode: mode)

        guard settingsStore.autoExtractIssues else {
            return .success(session)
        }

        do {
            session = try await extractIssuesAfterTranscription(for: session, apiKey: apiKey)
            return .success(session)
        } catch {
            return .postTranscriptionFailure(error)
        }
    }

    private func recordCompletedTranscriptionIfNeeded(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) {
        guard mode.recordsCompletionTelemetry else {
            return
        }

        transcriptionLogger.info(
            .transcriptionCompleted,
            "BugNarrator finished transcription and created a transcript session.",
            metadata: [
                "session_id": session.id.uuidString,
                "marker_count": "\(session.markerCount)",
                "screenshot_count": "\(session.screenshotCount)"
            ]
        )
        telemetryRecorder.record(
            .transcriptionCompleted,
            metadata: [
                "marker_count": "\(session.markerCount)",
                "screenshot_count": "\(session.screenshotCount)",
                "model": session.model
            ]
        )
    }

    private func persistInitialPostTranscriptionSession(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) throws {
        switch mode {
        case .finishedRecording:
            try persistCompletedTranscript(session)
        case .retry:
            try persistUpdatedSession(session)
            if settingsStore.autoCopyTranscript {
                clipboardService.copy(session.transcript)
            }
        }
    }

    private func finalizeInitialPostTranscriptionPersistence(
        _ session: TranscriptSession,
        mode: PostTranscriptionPipelineMode
    ) {
        guard mode == .finishedRecording else {
            return
        }

        sessionLibrary.setCurrentTranscript(session)
        recordingSessionController.clearActiveRecordingSession()
        showTranscriptWindow?()
    }

    private func extractIssuesAfterTranscription(
        for session: TranscriptSession,
        apiKey: String
    ) async throws -> TranscriptSession {
        var session = session
        setStatus(.transcribing(transcriptionProgressMessage(step: 3, action: "Extracting reviewable issues...")))
        swapActivity(reason: "Extracting review issues")

        let extraction = try await issueExtractionController.extractIssues(
            for: session,
            apiKey: apiKey,
            model: settingsStore.issueExtractionModelValue,
            apiBaseURL: settingsStore.openAIBaseURLValue,
            completionLog: .postTranscription
        )
        session.issueExtraction = extraction
        return session
    }

    private func finishSuccessfulTranscription(showTranscriptWindow: Bool) {
        if showTranscriptWindow {
            self.showTranscriptWindow?()
        }

        endActivity()
        setStatus(.success(transcriptionSuccessMessage()))
    }

    private func transcriptionSuccessMessage() -> String {
        if settingsStore.autoExtractIssues {
            return "Session saved. Transcript and extracted issues are ready."
        }

        if settingsStore.autoCopyTranscript {
            return "Session saved. Transcript copied to the clipboard."
        }

        return "Session saved locally and ready for review."
    }

    private func handleCompletedTranscriptPersistenceFailure(
        _ error: Error,
        session: TranscriptSession
    ) {
        sessionLibrary.stageCurrentTranscript(session)
        recordingSessionController.clearActiveRecordingSession()

        if settingsStore.autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }

        cleanupPendingRecordedAudioIfNeeded()
        endActivity()

        let normalizedError = errorPresenter.normalizeError(
            error,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )
        let appError = normalizedError.appError
        errorPresenter.logAppError(normalizedError, context: "transcript_persist_failed")
        var metadata = errorPresenter.appErrorMetadata(for: normalizedError, context: "transcript_persist_failed")
        metadata["session_id"] = session.id.uuidString
        sessionLibraryLogger.error(
            "transcript_persist_failed",
            "Transcription succeeded, but saving the transcript locally failed.",
            metadata: metadata
        )
        setStatus(.error("Transcript ready, but \(appError.userMessage)"), error: appError)
        showTranscriptWindow?()
    }

    private func handleFinishedRecordingPostTranscriptionResult(
        _ result: PostTranscriptionPipelineResult
    ) {
        switch result {
        case .success:
            cleanupPendingRecordedAudioIfNeeded()
            finishSuccessfulTranscription(showTranscriptWindow: false)
        case .persistenceFailure(let session, let error):
            handleCompletedTranscriptPersistenceFailure(error, session: session)
        case .postTranscriptionFailure(let error):
            cleanupPendingRecordedAudioIfNeeded()
            endActivity()
            presentPostTranscriptionError(error, operation: .postTranscription)
        }
    }

    private func handleStopSessionFailure(
        _ error: Error,
        recordingSession: RecordingSessionDraft,
        request: TranscriptionRequest
    ) {
        if let failureReason = transcriptionRecovery.recoverablePendingTranscriptionReason(for: error),
           let recordedAudio = recordingSessionController.pendingRecordedAudioSnapshot {
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
        recordingSessionController.clearActiveRecordingSession()
        if recordingSessionController.pendingRecordedAudioSnapshot == nil {
            presentError(error, operation: .recordingStop, fallback: { .recordingFailure($0) })
        } else {
            presentError(error, operation: .transcription)
        }
    }

    private func logPendingTranscriptionRetryRequested(
        _ context: PendingTranscriptionRetryContext
    ) {
        transcriptionLogger.info(
            "transcription_retry_requested",
            "Retrying transcription from preserved audio.",
            metadata: [
                "session_id": context.session.id.uuidString,
                "failure_reason": context.pendingTranscription.failureReason.rawValue,
                "attempt_count": "\(context.pendingTranscription.attemptCount + 1)"
            ]
        )
    }

    private func handlePendingTranscriptionRetryFailure(
        _ error: Error,
        context: PendingTranscriptionRetryContext
    ) -> Bool {
        guard let retryFailure = transcriptionRecovery.recordRetryableFailure(error, context: context) else {
            return false
        }

        endActivity()

        let appError = retryFailure.appError
        errorPresenter.logAppError(appError, context: "retry_pending_transcription", operation: .retryTranscription)
        setStatus(.error(retryFailure.statusMessage), error: appError)
        showTranscriptWindow?()
        showSettingsWindow?()
        return true
    }

    private func preserveRetryableSession(
        from recordingSession: RecordingSessionDraft,
        recordedAudio: RecordedAudio,
        request: TranscriptionRequest,
        failureReason: PendingTranscriptionFailureReason
    ) {
        switch transcriptionRecovery.preserveRetryableSession(
            from: recordingSession,
            recordedAudio: recordedAudio,
            request: request,
            failureReason: failureReason
        ) {
        case .preserved(let retryableSession, let appError):
            recordingSessionController.clearActiveRecordingSession()
            cleanupPendingRecordedAudioIfNeeded()
            endActivity()
            errorPresenter.logAppError(appError, context: "preserve_retryable_session", operation: .transcription)
            setStatus(.error(retryableSession.transcriptionRecoveryMessage ?? appError.userMessage), error: appError)
            showTranscriptWindow?()
            if appError.suggestsOpenAISettings {
                showSettingsWindow?()
            }

        case .persistenceFailure(let retryableSession, let error):
            recordingSessionController.clearActiveRecordingSession()
            cleanupPendingRecordedAudioIfNeeded()
            endActivity()

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
            setStatus(
                .error("Recording preserved, but \(persistenceError.userMessage)"),
                error: persistenceError
            )
            showTranscriptWindow?()
            if failureReason.appError.suggestsOpenAISettings {
                showSettingsWindow?()
            }

        case .preservationFailure(let error):
            if !settingsStore.debugMode {
                artifactsService.removeArtifactsDirectory(at: recordingSession.artifactsDirectoryURL)
            }
            recordingSessionController.clearActiveRecordingSession()
            presentError(error, operation: .recordingStop)
        }
    }

    private func persistCompletedTranscript(_ session: TranscriptSession) throws {
        try sessionLibrary.persistCompletedTranscript(
            session,
            autoCopyTranscript: settingsStore.autoCopyTranscript
        )
    }

    private func persistUpdatedSession(_ session: TranscriptSession) throws {
        try sessionLibrary.persistUpdatedSession(session)
    }

    private func sessionSnapshot(with sessionID: UUID) -> TranscriptSession? {
        sessionLibrary.sessionSnapshot(with: sessionID)
    }

    private func cancelPendingScreenshotSelection(reason: String) {
        screenshotCoordinator.cancelPendingSelection(reason: reason)
    }

    private func showToast(_ message: String, style: TransientToastStyle = .success) {
        toastDismissTask?.cancel()
        presentationState.showToast(TransientToast(message: message, style: style))
        toastDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            self?.presentationState.dismissToast()
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
        permissionRecoveryController.microphoneRecoveryGuidance(currentError: currentError)
    }

    private func validateRuntimeConfiguration() {
        permissionRecoveryController.validateRuntimeConfiguration()
    }

    private func logLaunchDiagnostics() {
        permissionRecoveryController.logLaunchPermissionSnapshot()

        sessionLibraryLogger.info(
            "launch_session_store_snapshot",
            "Captured the initial session library state at launch.",
            metadata: [
                "stored_session_count": "\(transcriptStore.sessionCount)",
                "selected_transcript_id": selectedTranscriptID?.uuidString ?? "none"
            ]
        )
    }

    private func importRecoveredRecordingsAtLaunch() {
        do {
            let outcome = try recoveredRecordingImportController.importRecoveredRecordingsAtLaunch()
            guard case .imported(let message, let error) = outcome else {
                return
            }

            setStatus(.error(message), error: error)
            showTranscriptWindow?()
        } catch {
            let normalizedError = errorPresenter.normalizeError(
                error,
                operation: .recoveredRecordingImport,
                fallback: { .storageFailure($0) }
            )
            let appError = normalizedError.appError
            errorPresenter.logAppError(normalizedError, context: "recovered_recording_import_failed")
            sessionLibraryLogger.error(
                "recovered_recording_import_failed",
                appError.userMessage,
                metadata: errorPresenter.appErrorMetadata(for: normalizedError, context: "recovered_recording_import_failed")
            )
            setStatus(.error(appError.userMessage), error: appError)
        }
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
