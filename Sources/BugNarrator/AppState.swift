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
    let transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter
    let transientToastController: TransientToastController
    let recordingSessionController: RecordingSessionController
    let recordingSessionStartStatusPresenter: RecordingSessionStartStatusPresenter
    let recordingSessionStopReadinessPresenter: RecordingSessionStopReadinessPresenter
    let recordingSessionCancelStatusPresenter: RecordingSessionCancelStatusPresenter
    let recordingStatusMessages: RecordingStatusMessageProvider
    let sessionLibrary: SessionLibraryController
    let sessionLibraryStatusPresenter: SessionLibraryStatusPresenter
    let exportHistoryController: ExportHistoryController
    let recoveredRecordingImportController: RecoveredRecordingImportController
    private let recoveredRecordingLaunchImporter: RecoveredRecordingLaunchImportPresenter
    let issueExtractionController: IssueExtractionController
    let manualIssueExtractionStatusPresenter: ManualIssueExtractionStatusPresenter
    let issueExportController: IssueExportController
    let issueExportPresentationController: IssueExportPresentationController
    let permissionRecoveryController: PermissionRecoveryController
    let appUtilityActions: AppUtilityActionController
    let appUtilityActionPresenter: AppUtilityActionResultPresenter
    let applicationTerminationController: ApplicationTerminationController
    let supportDataController: SupportDataController
    let supportDataActionPresenter: SupportDataActionPresenter
    let localDataDeletionController: LocalDataDeletionController
    let transcriptionRecovery: TranscriptionRecoveryController
    let retryTranscriptionStatusPresenter: RetryTranscriptionStatusPresenter
    let retryableSessionPreservationPresenter: RetryableSessionPreservationPresenter
    let screenshotCoordinator: ScreenshotCoordinator
    let screenshotCaptureController: ScreenshotCaptureController

    var showTranscriptWindow: (() -> Void)? { get { appUtilityActions.showTranscriptWindow } set { appUtilityActions.showTranscriptWindow = newValue } }
    var showSettingsWindow: (() -> Void)? { get { appUtilityActions.showSettingsWindow } set { appUtilityActions.showSettingsWindow = newValue } }
    var showAboutWindow: (() -> Void)? { get { appUtilityActions.showAboutWindow } set { appUtilityActions.showAboutWindow = newValue } }
    var showChangelogWindow: (() -> Void)? { get { appUtilityActions.showChangelogWindow } set { appUtilityActions.showChangelogWindow = newValue } }
    var showSupportWindow: (() -> Void)? { get { appUtilityActions.showSupportWindow } set { appUtilityActions.showSupportWindow = newValue } }
    var showRecordingControlWindow: (() -> Void)? { get { appUtilityActions.showRecordingControlWindow } set { appUtilityActions.showRecordingControlWindow = newValue } }

    var prepareForScreenshotSelection: (() -> Void)? {
        get { screenshotCaptureController.prepareForScreenshotSelection }
        set { screenshotCaptureController.prepareForScreenshotSelection = newValue }
    }
    var restoreAfterScreenshotSelection: (() -> Void)? {
        get { screenshotCaptureController.restoreAfterScreenshotSelection }
        set { screenshotCaptureController.restoreAfterScreenshotSelection = newValue }
    }

    private let transcriptionClient: any TranscriptionServing
    private let hotkeyManager: any HotkeyManaging
    private let hotkeySettingsBinder: HotkeySettingsBinder
    private let objectChangeForwarder: ObservableObjectChangeForwarder
    private let lifecycleNotificationBinder: AppLifecycleNotificationBinder
    private let launchDiagnosticsReporter: AppLaunchDiagnosticsReporter
    private let artifactsService: any SessionArtifactsManaging
    private let telemetryRecorder: any OperationalTelemetryRecording

    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let transcriptionLogger = DiagnosticsLogger(category: .transcription)
    private let settingsLogger = DiagnosticsLogger(category: .settings)

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
        let transientToastController = TransientToastController(presentationState: presentationState)
        self.transientToastController = transientToastController
        let recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: microphonePermissionService,
            artifactsService: artifactsService,
            recordingTimer: recordingTimer
        )
        self.recordingSessionController = recordingSessionController
        self.recordingSessionStopReadinessPresenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: self.errorPresenter
        )
        self.recordingSessionCancelStatusPresenter = RecordingSessionCancelStatusPresenter(
            setStatus: { status in presentationState.setStatus(status, error: nil) }
        )
        let recordingStatusMessages = RecordingStatusMessageProvider {
            RecordingStatusMessageSnapshot(
                audioSource: settingsStore.recordingAudioSource,
                hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
                aiProviderCompatibilityIssue: settingsStore.aiProviderCompatibilityIssue,
                autoExtractIssues: settingsStore.autoExtractIssues,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
        }
        self.recordingStatusMessages = recordingStatusMessages
        self.recordingSessionStartStatusPresenter = RecordingSessionStartStatusPresenter(
            errorPresenter: self.errorPresenter,
            recordingStatusMessages: recordingStatusMessages,
            startDiagnosticsMetadata: {
                [
                    "audio_source": settingsStore.recordingAudioSource.diagnosticsValue,
                    "has_ai_provider_credential": settingsStore.hasUsableAIProviderCredential ? "yes" : "no",
                    "ai_provider": settingsStore.aiProvider.rawValue
                ]
            },
            telemetryRecorder: telemetryRecorder
        )
        let sessionLibrary = SessionLibraryController(
            transcriptStore: transcriptStore,
            artifactsService: artifactsService,
            clipboardService: clipboardService
        )
        self.sessionLibrary = sessionLibrary
        self.sessionLibraryStatusPresenter = SessionLibraryStatusPresenter(
            errorPresenter: self.errorPresenter
        )
        self.exportHistoryController = ExportHistoryController(exportService: exportService)
        let recoveredRecordingImportController = RecoveredRecordingImportController(
            transcriptStore: transcriptStore,
            sessionLibrary: sessionLibrary,
            recoveredRecordingImporter: recoveredRecordingImporter,
            artifactsService: artifactsService
        )
        self.recoveredRecordingImportController = recoveredRecordingImportController
        let issueExtractionController = IssueExtractionController(
            sessionLibrary: sessionLibrary,
            issueExtractionService: issueExtractionService
        )
        self.issueExtractionController = issueExtractionController
        let issueExportController = IssueExportController(
            settingsStore: settingsStore,
            sessionLibrary: sessionLibrary,
            exportService: exportService
        )
        self.issueExportController = issueExportController
        let permissionRecoveryController = PermissionRecoveryController(
            microphonePermissionService: microphonePermissionService,
            screenCapturePermissionService: screenCapturePermissionService,
            urlHandler: urlHandler,
            runtimeEnvironment: runtimeEnvironment
        )
        self.permissionRecoveryController = permissionRecoveryController
        self.launchDiagnosticsReporter = AppLaunchDiagnosticsReporter(
            permissionRecoveryController: permissionRecoveryController,
            transcriptStore: transcriptStore
        )
        let appUtilityActions = AppUtilityActionController(
            urlHandler: urlHandler,
            permissionRecoveryController: permissionRecoveryController
        )
        self.appUtilityActions = appUtilityActions
        self.manualIssueExtractionStatusPresenter = ManualIssueExtractionStatusPresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.issueExportPresentationController = IssueExportPresentationController(
            errorPresenter: self.errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.transcriptPersistenceFailurePresenter = TranscriptPersistenceFailurePresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        self.recoveredRecordingLaunchImporter = RecoveredRecordingLaunchImportPresenter(
            importController: recoveredRecordingImportController,
            errorPresenter: self.errorPresenter,
            setStatus: { status, error in
                presentationState.setStatus(status, error: error)
            },
            openTranscriptHistory: {
                appUtilityActions.openTranscriptHistory()
            }
        )
        let appUtilityActionPresenter = AppUtilityActionResultPresenter(
            statusPhase: { presentationState.status.phase },
            setStatus: { status in
                presentationState.setStatus(status, error: nil)
            }
        )
        self.appUtilityActionPresenter = appUtilityActionPresenter
        self.supportDataActionPresenter = SupportDataActionPresenter(
            presentationState: presentationState,
            utilityActions: appUtilityActions,
            utilityResultPresenter: appUtilityActionPresenter
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
            sessionLibrary: sessionLibrary,
            supportDataController: self.supportDataController,
            exportHistoryController: self.exportHistoryController
        )
        self.transcriptionRecovery = TranscriptionRecoveryController(
            sessionLibrary: sessionLibrary,
            artifactsService: artifactsService
        )
        self.retryTranscriptionStatusPresenter = RetryTranscriptionStatusPresenter(
            errorPresenter: self.errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() },
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        self.retryableSessionPreservationPresenter = RetryableSessionPreservationPresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        let screenshotCoordinator = ScreenshotCoordinator(
            screenCapturePermissionService: screenCapturePermissionService,
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: screenshotSelectionService,
            artifactsService: artifactsService
        )
        self.screenshotCoordinator = screenshotCoordinator
        self.screenshotCaptureController = ScreenshotCaptureController(
            screenshotCoordinator: screenshotCoordinator,
            recordingSessionController: recordingSessionController,
            errorPresenter: self.errorPresenter,
            statusPhase: { presentationState.status.phase },
            elapsedDuration: { recordingTimer.elapsedDuration },
            recordingDetailMessage: {
                recordingStatusMessages.recordingDetailMessage()
            },
            setStatus: { status, error in
                presentationState.setStatus(status, error: error)
            },
            showToast: { message, style in
                transientToastController.showToast(message, style: style)
            }
        )
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.hotkeySettingsBinder = HotkeySettingsBinder(hotkeyManager: hotkeyManager)
        self.objectChangeForwarder = ObservableObjectChangeForwarder()
        self.lifecycleNotificationBinder = AppLifecycleNotificationBinder()
        self.artifactsService = artifactsService
        self.telemetryRecorder = telemetryRecorder
        self.trackerIntegration = TrackerIntegrationController(
            settingsStore: settingsStore,
            exportService: exportService
        )
        self.aiProviderSettings = AIProviderSettingsController(
            settingsStore: settingsStore,
            transcriptionClient: transcriptionClient
        )
        let applicationTerminationController = ApplicationTerminationController(
            statusPhase: { presentationState.status.phase },
            activeRecordingSession: { recordingSessionController.activeRecordingSession },
            isExtractingIssues: { issueExtractionController.issueExtractionSessionID != nil },
            isExporting: { issueExportController.exportDestinationInProgress != nil },
            cancelPendingScreenshotSelection: { reason in
                screenshotCoordinator.cancelPendingSelection(reason: reason)
            },
            showRecordingControls: {
                appUtilityActions.openRecordingControls()
            },
            showToast: { message, style in
                transientToastController.showToast(message, style: style)
            },
            dismissToast: {
                transientToastController.dismissToast()
            },
            unregisterHotkeys: {
                hotkeyManager.unregisterAll()
            },
            stopTimer: { resetElapsed in
                recordingSessionController.stopTimer(resetElapsed: resetElapsed)
            },
            endActivity: {
                recordingSessionController.endActivity()
            }
        )
        self.applicationTerminationController = applicationTerminationController

        BugNarratorDiagnostics.setDebugModeEnabled(settingsStore.debugMode)

        let hotkeyActionDispatcher = HotkeyActionDispatcher(
            statusPhase: { [weak self] in
                self?.status.phase ?? .idle
            },
            startRecording: { [weak self] in
                await self?.openRecordingControlsAndStartSession()
            },
            stopRecording: { [weak self] in
                await self?.stopSession()
            },
            captureScreenshot: { [weak self] in
                await self?.captureScreenshot()
            }
        )
        self.hotkeyManager.onHotKeyPressed = { action in
            Task { @MainActor in
                hotkeyActionDispatcher.handle(action)
            }
        }

        trackerIntegration.showSettingsWindow = { [weak self] in
            self?.showSettingsWindow?()
        }

        aiProviderSettings.showSettingsWindow = { [weak self] in
            self?.showSettingsWindow?()
        }

        objectChangeForwarder.forward(
            [
                trackerIntegration.objectWillChange,
                aiProviderSettings.objectWillChange,
                presentationState.objectWillChange,
                recordingSessionController.objectWillChange,
                sessionLibrary.objectWillChange,
                exportHistoryController.objectWillChange,
                recoveredRecordingImportController.objectWillChange,
                issueExtractionController.objectWillChange,
                issueExportController.objectWillChange,
                transcriptionRecovery.objectWillChange,
                screenshotCoordinator.objectWillChange
            ],
            notify: { [weak self] in
                self?.objectWillChange.send()
            }
        )

        lifecycleNotificationBinder.bind(
            didBecomeActive: { [weak self] in
                self?.refreshPermissionRecoveryState()
            },
            willTerminate: {
                applicationTerminationController.prepareForApplicationTermination()
            }
        )

        hotkeySettingsBinder.bind(settingsStore: settingsStore)

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
        permissionRecoveryController.validateRuntimeConfiguration()
        recoveredRecordingLaunchImporter.importRecoveredRecordingsAtLaunch()
        Task { [weak self] in
            await self?.refreshExportHistory()
        }
        launchDiagnosticsReporter.logLaunchDiagnostics(selectedTranscriptID: selectedTranscriptID)
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
        screenshotCaptureController.isCaptureInProgress
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
            activityReason: recordingStatusMessages.recordingActivityReason()
        )
        recordingSessionStartStatusPresenter.present(outcome)
    }

    func stopSession() async {
        guard let recordingSession = beginStoppingSession() else {
            return
        }

        defer { recordingSessionController.finishStoppingSession() }

        screenshotCaptureController.cancelPendingSelection(
            reason: "Stopping the active session cancels pending screenshot selection."
        )
        recordingSessionController.prepareForStopSession()
        let request = settingsStore.transcriptionRequest

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

            setStatus(.transcribing(recordingStatusMessages.transcriptionUploadProgressMessage()))
            recordingSessionController.swapActivity(reason: "Uploading audio for transcription")

            let transcriptionResult = try await transcriptionClient.transcribe(
                fileURL: recordedAudio.fileURL,
                apiKey: apiKey,
                request: request
            )
            let session = TranscriptionSessionBuilder.completedSession(
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
                self?.screenshotCaptureController.cancelPendingSelection(
                    reason: "Discarding the active session cancels pending screenshot selection."
                )
            }
        )

        recordingSessionCancelStatusPresenter.present(outcome)
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
        applicationTerminationController.requestApplicationTermination()
    }

    func applicationShouldTerminate() -> NSApplication.TerminateReply {
        applicationTerminationController.applicationShouldTerminate()
    }

    func openAbout() {
        appUtilityActions.openAbout()
    }

    func openChangelog() {
        appUtilityActions.openChangelog()
    }

    func openGitHubRepository() {
        appUtilityActionPresenter.present(appUtilityActions.openGitHubRepository())
    }

    func openDocumentation() {
        appUtilityActionPresenter.present(appUtilityActions.openDocumentation())
    }

    func openIssueReporter() {
        appUtilityActionPresenter.present(appUtilityActions.openIssueReporter())
    }

    func openSupportDevelopment() {
        appUtilityActions.openSupportDevelopment()
    }

    func openSupportDonationPage() {
        appUtilityActionPresenter.present(appUtilityActions.openSupportDonationPage())
    }

    func openMicrophonePrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openMicrophonePrivacySettings())
    }

    func openScreenRecordingPrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openScreenRecordingPrivacySettings())
    }

    func openSystemAudioPrivacySettings() {
        appUtilityActionPresenter.present(appUtilityActions.openSystemAudioPrivacySettings())
    }

    func checkForUpdates() {
        appUtilityActionPresenter.present(appUtilityActions.checkForUpdates())
    }

    func copyDebugInfo() {
        let result = supportDataController.copyDebugInfo(sessionID: currentDebugSessionID)
        supportDataActionPresenter.presentCopyDebugInfo(result)
    }

    func exportDebugBundle() async {
        do {
            guard let completion = try await supportDataController.exportDebugBundle(
                sessionMetadata: currentDebugSessionMetadata()
            ) else {
                return
            }

            supportDataActionPresenter.presentDebugBundleExport(completion)
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

            supportDataActionPresenter.presentPrivacyDataExport(completion)
        } catch {
            presentError(
                error,
                operation: .privacyExport,
                fallback: { _ in .exportFailure("BugNarrator could not create the data export.") }
            )
        }
    }

    func deleteAllLocalData() async {
        do {
            let result = try await localDataDeletionController.deleteAllLocalData(
                currentTranscript: currentTranscript,
                statusPhase: status.phase
            )
            supportDataActionPresenter.presentLocalDataDeletion(result)
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
        sessionLibraryStatusPresenter.presentDisplayedTranscriptCopyResult(sessionLibrary.copyDisplayedTranscript())
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
            retryTranscriptionStatusPresenter.presentRetryContextFailure(
                appError: appError,
                opensSettings: opensSettings,
                statusMessage: statusMessage
            )
            return
        }

        guard transcriptionRecovery.beginRetry(for: sessionID) else {
            return
        }

        let request = settingsStore.transcriptionRequest
        sessionLibrary.stageCurrentTranscript(retryContext.session)
        setStatus(.transcribing(recordingStatusMessages.transcriptionRetryProgressMessage()))
        recordingSessionController.swapActivity(reason: "Retrying transcription from preserved audio")
        logPendingTranscriptionRetryRequested(retryContext)

        do {
            guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
                throw AppError.missingAPIKey
            }

            let result = try await transcriptionClient.transcribe(
                fileURL: retryContext.audioFileURL,
                apiKey: apiKey,
                request: request
            )
            let updatedSession = TranscriptionSessionBuilder.recoveredSession(
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
                recordingSessionController.endActivity()
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
            sessionLibraryStatusPresenter.presentSavedSession(try sessionLibrary.saveCurrentTranscriptToHistory())
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }

    func deleteDisplayedTranscript() {
        do {
            sessionLibraryStatusPresenter.presentDeletedCount(try sessionLibrary.deleteDisplayedTranscript())
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        do {
            sessionLibraryStatusPresenter.presentDeletedCount(try sessionLibrary.deleteSessions(withIDs: ids))
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }

    func captureScreenshot() async {
        await screenshotCaptureController.captureScreenshot()
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
            manualIssueExtractionStatusPresenter.presentRequestStarted(sessionID: transcriptSession.id)
            recordingSessionController.beginActivity(reason: "Extracting review issues")

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

                recordingSessionController.endActivity()
                manualIssueExtractionStatusPresenter.presentCompletion(issueCount: extraction.issues.count)
            } catch {
                manualIssueExtractionStatusPresenter.presentFailure(error)
            }

            return
        }

        manualIssueExtractionStatusPresenter.presentPreflightFailure(preflightError, sessionID: transcriptSession.id)
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
            issueExportPresentationController.presentPreflightFailure(failure)
            return
        }

        issueExportPresentationController.presentReviewPreparation(destination: destination)
        recordingSessionController.beginActivity(reason: "Reviewing similar issues before export")

        do {
            let review = try await issueExportController.prepareIssueExportReview(
                for: context,
                model: settingsStore.issueExtractionModelValue,
                apiBaseURL: settingsStore.openAIBaseURLValue
            )
            recordingSessionController.endActivity()

            if review.hasMatches {
                issueExportPresentationController.presentReviewReady(destination: destination)
            } else {
                await finalizeIssueExport(using: review)
            }
        } catch {
            recordingSessionController.endActivity()
            issueExportPresentationController.presentFailure(error)
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
                issueExportPresentationController.presentRemoteExportStarted(destination: review.destination)
                recordingSessionController.beginActivity(reason: "Exporting extracted issues")
            }

            let completion = try await issueExportController.finalizeIssueExport(using: review)
            if completion.performedRemoteExport {
                recordingSessionController.endActivity()
            }

            issueExportPresentationController.presentCompletion(completion)
            await refreshExportHistory()
        } catch {
            recordingSessionController.endActivity()
            issueExportPresentationController.presentFailure(error)
        }
    }

    func openScreenshot(_ screenshot: SessionScreenshot) {
        appUtilityActionPresenter.present(appUtilityActions.openScreenshot(screenshot))
    }

    private func setStatus(_ newStatus: AppStatus, error: AppError? = nil) {
        errorPresenter.setStatus(newStatus, error: error)
    }

    private func presentError(
        _ error: Error,
        operation: AppErrorOperation = .generic,
        fallback: (String) -> AppError = { .transcriptionFailure($0) }
    ) {
        recordingSessionController.stopTimer(resetElapsed: status.phase == .recording)
        recordingSessionController.endActivity()
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

    private func logSessionStopRequested(_ recordingSession: RecordingSessionDraft) {
        recordingLogger.info(
            .sessionStopRequested,
            "Stopping the active feedback session.",
            metadata: ["session_id": recordingSession.sessionID.uuidString]
        )
    }

    private func beginStoppingSession() -> RecordingSessionDraft? {
        recordingSessionStopReadinessPresenter.recordingSession(
            for: recordingSessionController.beginStoppingSession(statusPhase: status.phase)
        )
    }

    private func completePostTranscriptionPipeline(
        session: TranscriptSession,
        apiKey: String,
        mode: PostTranscriptionPipelineMode
    ) async -> PostTranscriptionPipelineResult {
        var session = session
        recordCompletedTranscriptionIfNeeded(session, mode: mode)
        setStatus(.transcribing(recordingStatusMessages.transcriptionSavingProgressMessage(mode: mode)))

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
            try sessionLibrary.persistCompletedTranscript(
                session,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
        case .retry:
            try sessionLibrary.persistUpdatedSession(
                session,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
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
        setStatus(.transcribing(recordingStatusMessages.transcriptionIssueExtractionProgressMessage()))
        recordingSessionController.swapActivity(reason: "Extracting review issues")

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

        recordingSessionController.endActivity()
        setStatus(.success(recordingStatusMessages.transcriptionSuccessMessage()))
    }

    private func handleCompletedTranscriptPersistenceFailure(
        _ error: Error,
        session: TranscriptSession
    ) {
        sessionLibrary.stageCurrentTranscript(
            session,
            autoCopyTranscript: settingsStore.autoCopyTranscript
        )
        recordingSessionController.clearActiveRecordingSession()

        cleanupPendingRecordedAudioIfNeeded()
        recordingSessionController.endActivity()

        transcriptPersistenceFailurePresenter.present(error, sessionID: session.id)
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
            recordingSessionController.endActivity()
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

        recordingSessionController.endActivity()
        retryTranscriptionStatusPresenter.presentRetryableFailure(retryFailure)
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
            recordingSessionController.endActivity()
            retryableSessionPreservationPresenter.presentPreservedSession(retryableSession, appError: appError)

        case .persistenceFailure(let retryableSession, let error):
            recordingSessionController.clearActiveRecordingSession()
            cleanupPendingRecordedAudioIfNeeded()
            recordingSessionController.endActivity()
            retryableSessionPreservationPresenter.presentPersistenceFailure(
                error,
                retryableSession: retryableSession,
                recoveryAppError: failureReason.appError
            )

        case .preservationFailure(let error):
            if !settingsStore.debugMode {
                artifactsService.removeArtifactsDirectory(at: recordingSession.artifactsDirectoryURL)
            }
            recordingSessionController.clearActiveRecordingSession()
            presentError(error, operation: .recordingStop)
        }
    }

    private var currentDebugSessionID: UUID? {
        DebugSessionContextProvider.currentSessionID(
            activeRecordingSession: activeRecordingSession,
            displayedTranscript: displayedTranscript,
            currentTranscript: currentTranscript
        )
    }

    private func currentDebugSessionMetadata() -> DebugSessionMetadata {
        DebugSessionContextProvider.metadata(
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

}
