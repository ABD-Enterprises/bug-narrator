import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var showDiscardConfirmation = false
    @Published var isPresentingSystemAudioExplainer = false
    private var systemAudioExplainerAcknowledged = false

    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let trackerIntegration: TrackerIntegrationController
    let aiProviderSettings: AIProviderSettingsController
    let recordingTimer: RecordingTimerViewModel
    let presentationState: AppPresentationState
    let errorPresenter: AppErrorPresenter
    let transcriptPersistenceFailurePresenter: TranscriptPersistenceFailurePresenter
    let postTranscriptionFailurePresenter: PostTranscriptionFailurePresenter
    let transientToastController: TransientToastController
    let recordingSessionController: RecordingSessionController
    let recordingSessionStartStatusPresenter: RecordingSessionStartStatusPresenter
    let recordingSessionStopReadinessPresenter: RecordingSessionStopReadinessPresenter
    let recordingSessionStopFailurePresenter: RecordingSessionStopFailurePresenter
    let recordingSessionCancelStatusPresenter: RecordingSessionCancelStatusPresenter
    let recordingStatusMessages: RecordingStatusMessageProvider
    let postTranscriptionStatusPresenter: PostTranscriptionStatusPresenter
    let postTranscriptionPipeline: PostTranscriptionPipelineController
    let finishedRecordingPostTranscriptionResultHandler: FinishedRecordingPostTranscriptionResultHandler
    let retryPostTranscriptionResultHandler: RetryPostTranscriptionResultHandler
    let sessionLibrary: SessionLibraryController
    let sessionLibraryStatusPresenter: SessionLibraryStatusPresenter
    let exportHistoryController: ExportHistoryController
    let issueExtractionController: IssueExtractionController
    let manualIssueExtractionStatusPresenter: ManualIssueExtractionStatusPresenter
    let issueExtractionFailurePresenter: IssueExtractionFailurePresenter
    let issueExportController: IssueExportController
    let issueExportPresentationController: IssueExportPresentationController
    let permissionRecoveryController: PermissionRecoveryController
    let permissionRecoveryStatusPresenter: PermissionRecoveryStatusPresenter
    let appUtilityActions: AppUtilityActionController
    let appUtilityActionPresenter: AppUtilityActionResultPresenter
    let applicationTerminationController: ApplicationTerminationController
    let supportDataController: SupportDataController
    let supportDataActionPresenter: SupportDataActionPresenter
    let localDataDeletionController: LocalDataDeletionController
    let transcriptionRecovery: TranscriptionRecoveryController
    let retryTranscriptionStatusPresenter: RetryTranscriptionStatusPresenter
    let pendingTranscriptionRetryFailureHandler: PendingTranscriptionRetryFailureHandler
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

    private let recordingLogger = DiagnosticsLogger(category: .recording)
    private let transcriptionLogger = DiagnosticsLogger(category: .transcription)
    private let settingsLogger = DiagnosticsLogger(category: .settings)

    var status: AppStatus {
        presentationState.status
    }

    var currentError: AppError? {
        presentationState.currentError
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
            telemetryRecorder: telemetryRecorder,
            provider: { [settingsStore] in settingsStore.aiProvider }
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
        self.permissionRecoveryStatusPresenter = PermissionRecoveryStatusPresenter(
            errorPresenter: self.errorPresenter
        )
        self.launchDiagnosticsReporter = AppLaunchDiagnosticsReporter(
            permissionRecoveryController: permissionRecoveryController,
            transcriptStore: transcriptStore
        )
        let appUtilityActions = AppUtilityActionController(
            urlHandler: urlHandler,
            permissionRecoveryController: permissionRecoveryController
        )
        self.appUtilityActions = appUtilityActions
        self.recordingSessionStopFailurePresenter = RecordingSessionStopFailurePresenter(
            errorPresenter: self.errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.postTranscriptionStatusPresenter = PostTranscriptionStatusPresenter(
            recordingStatusMessages: recordingStatusMessages,
            setStatus: { status in presentationState.setStatus(status, error: nil) },
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        self.postTranscriptionFailurePresenter = PostTranscriptionFailurePresenter(
            errorPresenter: self.errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.postTranscriptionPipeline = PostTranscriptionPipelineController(
            settingsStore: settingsStore,
            sessionLibrary: sessionLibrary,
            issueExtractionController: issueExtractionController,
            recordingSessionController: recordingSessionController,
            statusPresenter: self.postTranscriptionStatusPresenter,
            telemetryRecorder: telemetryRecorder,
            transcriptionLogger: transcriptionLogger
        )
        self.manualIssueExtractionStatusPresenter = ManualIssueExtractionStatusPresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.issueExtractionFailurePresenter = IssueExtractionFailurePresenter(
            errorPresenter: self.errorPresenter
        )
        self.issueExportPresentationController = IssueExportPresentationController(
            errorPresenter: self.errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        self.transcriptPersistenceFailurePresenter = TranscriptPersistenceFailurePresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        let appUtilityActionPresenter = AppUtilityActionResultPresenter(
            statusPhase: { presentationState.status.phase },
            setStatus: { status in
                presentationState.setStatus(status, error: nil)
            }
        )
        self.appUtilityActionPresenter = appUtilityActionPresenter
        self.finishedRecordingPostTranscriptionResultHandler = FinishedRecordingPostTranscriptionResultHandler(
            sessionLibrary: sessionLibrary,
            recordingSessionController: recordingSessionController,
            statusPresenter: self.postTranscriptionStatusPresenter,
            transcriptPersistenceFailurePresenter: self.transcriptPersistenceFailurePresenter,
            postTranscriptionFailurePresenter: self.postTranscriptionFailurePresenter,
            autoCopyTranscript: { settingsStore.autoCopyTranscript },
            cleanupPendingRecordedAudio: {
                recordingSessionController.cleanupPendingRecordedAudioIfNeeded(debugMode: settingsStore.debugMode)
            },
            preserveRecordedAudioForReview: { session in
                // A low-quality transcript "succeeded" but is likely unusable;
                // preserve the recording into the session assets dir so it can be
                // re-transcribed. Only remove the pending temp after preservation
                // succeeds; on failure keep it so the recording is never lost (#466).
                guard let artifactsDirectoryURL = session.artifactsDirectoryURL,
                      let recordedAudio = recordingSessionController.pendingRecordedAudioSnapshot else {
                    return
                }

                let logger = DiagnosticsLogger(category: .transcription)
                do {
                    let preservedURL = try artifactsService.preserveRecordedAudio(
                        recordedAudio,
                        in: artifactsDirectoryURL
                    )
                    recordingSessionController.cleanupPendingRecordedAudioIfNeeded(debugMode: settingsStore.debugMode)
                    logger.info(
                        "low_quality_recording_preserved",
                        "Preserved the recording for a low-quality transcript so it can be re-transcribed.",
                        metadata: [
                            "session_id": session.id.uuidString,
                            "file_name": preservedURL.lastPathComponent
                        ]
                    )
                } catch {
                    logger.error(
                        "low_quality_recording_preserve_failed",
                        (error as? AppError)?.userMessage ?? error.localizedDescription,
                        metadata: ["session_id": session.id.uuidString]
                    )
                }
            },
            showSavedSessionReveal: { session in
                guard let artifactsDirectoryURL = session.artifactsDirectoryURL else {
                    return
                }

                transientToastController.showToast(
                    "Session saved",
                    style: .success,
                    durationNanoseconds: 5_000_000_000,
                    action: TransientToastAction(
                        title: "Reveal",
                        accessibilityLabel: "Reveal in Finder"
                    ) {
                        appUtilityActionPresenter.present(appUtilityActions.revealInFinder(artifactsDirectoryURL))
                    }
                )
            }
        )
        self.supportDataActionPresenter = SupportDataActionPresenter(
            presentationState: presentationState,
            errorPresenter: self.errorPresenter,
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
        self.pendingTranscriptionRetryFailureHandler = PendingTranscriptionRetryFailureHandler(
            transcriptionRecovery: self.transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            retryStatusPresenter: self.retryTranscriptionStatusPresenter,
            provider: { settingsStore.aiProvider }
        )
        self.retryableSessionPreservationPresenter = RetryableSessionPreservationPresenter(
            errorPresenter: self.errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() },
            provider: { settingsStore.aiProvider }
        )
        self.retryPostTranscriptionResultHandler = RetryPostTranscriptionResultHandler(
            transcriptionRecovery: self.transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            statusPresenter: self.postTranscriptionStatusPresenter,
            sessionLibraryStatusPresenter: self.sessionLibraryStatusPresenter,
            postTranscriptionFailurePresenter: self.postTranscriptionFailurePresenter,
            debugMode: { settingsStore.debugMode }
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

        recordingSessionStartStatusPresenter.showSettingsWindow = { [weak self] in
            self?.showSettingsWindow?()
        }
        recordingSessionStartStatusPresenter.prepareErrorPresentationSideEffects = { [weak self] in
            self?.prepareErrorPresentationSideEffects()
        }
        issueExtractionFailurePresenter.prepareErrorPresentationSideEffects = { [weak self] in
            self?.prepareErrorPresentationSideEffects()
        }
        sessionLibraryStatusPresenter.prepareErrorPresentationSideEffects = { [weak self] in
            self?.prepareErrorPresentationSideEffects()
        }

        objectChangeForwarder.forward(
            [
                settingsStore.objectWillChange,
                trackerIntegration.objectWillChange,
                aiProviderSettings.objectWillChange,
                presentationState.objectWillChange,
                recordingSessionController.objectWillChange,
                sessionLibrary.objectWillChange,
                exportHistoryController.objectWillChange,
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
                // Best-effort: flush any debounced diagnostics before quitting.
                Task { await BugNarratorDiagnostics.store.flush() }
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
        settingsStore.aiProviderCompatibilityIssue != nil ||
            (settingsStore.aiProvider.requiresAPIKey && !settingsStore.hasUsableAIProviderCredential)
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

    var activeRecordingSession: RecordingSessionDraft? {
        recordingSessionController.activeRecordingSession
    }

    var isScreenshotCaptureInProgress: Bool {
        screenshotCaptureController.isCaptureInProgress
    }

    func refreshPermissionRecoveryState() {
        permissionRecoveryStatusPresenter.present(
            permissionRecoveryController.refreshRecoveryState(
                currentError: currentError,
                statusPhase: status.phase
            )
        )
    }

    func startSession() async {
        recordingLogger.info(.sessionStartRequested, "A feedback session start was requested.")

        if let compatibilityIssue = settingsStore.aiProviderCompatibilityIssue {
            let appError = AppError.transcriptionFailure(compatibilityIssue)
            errorPresenter.setStatus(.error(compatibilityIssue), error: appError)
            showSettingsWindow?()
            return
        }

        guard settingsStore.hasUsableAIProviderCredential else {
            let appError = AppError.missingAPIKey
            errorPresenter.setStatus(.error(appError.userMessage(for: settingsStore.aiProvider)), error: appError)
            showSettingsWindow?()
            return
        }

        if settingsStore.shouldShowSystemAudioExplainer(
            for: settingsStore.recordingAudioSource,
            acknowledged: systemAudioExplainerAcknowledged
        ) {
            isPresentingSystemAudioExplainer = true
            return
        }
        systemAudioExplainerAcknowledged = false

        let outcome = await recordingSessionController.startSession(
            statusPhase: status.phase,
            activityReason: recordingStatusMessages.recordingActivityReason()
        )
        recordingSessionStartStatusPresenter.present(outcome)
    }

    /// User dismissed the system-audio explainer; proceed with the recording.
    func confirmSystemAudioExplainer(suppressFuture: Bool) async {
        if suppressFuture {
            settingsStore.suppressSystemAudioExplainer = true
        }
        systemAudioExplainerAcknowledged = true
        isPresentingSystemAudioExplainer = false
        await startSession()
    }

    func cancelSystemAudioExplainer() {
        isPresentingSystemAudioExplainer = false
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

            if settingsStore.aiProviderCompatibilityIssue != nil {
                preserveRetryableSession(
                    from: recordingSession,
                    recordedAudio: recordedAudio,
                    request: request,
                    failureReason: .providerSetup
                )
                return
            }

            guard let apiKey = settingsStore.aiProviderCredentialForUserInitiatedAccess() else {
                preserveRetryableSession(
                    from: recordingSession,
                    recordedAudio: recordedAudio,
                    request: request,
                    failureReason: .missingAPIKey
                )
                return
            }

            postTranscriptionStatusPresenter.presentUploadProgress()
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
            let result = await postTranscriptionPipeline.complete(
                session: session,
                apiKey: apiKey,
                mode: .finishedRecording
            )
            finishedRecordingPostTranscriptionResultHandler.handle(result)
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

    func openRecordingControlsAndStartSession() async {
        appUtilityActions.openRecordingControls()

        guard status.phase != .recording else {
            return
        }

        await startSession()
    }

    /// Presents the changelog once after a version bump. Records the shown
    /// version immediately so a force-quit before dismissal does not re-trigger.
    func presentChangelogIfNeeded(metadata: BugNarratorMetadata = BugNarratorMetadata()) {
        let hasExistingUserState = !transcriptStore.sessions.isEmpty
        guard settingsStore.shouldAutoShowChangelog(
            currentVersion: metadata.version,
            hasExistingUserState: hasExistingUserState
        ) else {
            return
        }

        settingsStore.markChangelogShown(version: metadata.version)
        showChangelogWindow?()
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
            supportDataActionPresenter.presentDebugBundleExportFailure(error)
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
            supportDataActionPresenter.presentPrivacyDataExportFailure(error)
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
            supportDataActionPresenter.presentLocalDataDeletionFailure(error)
        }
    }

    func refreshExportHistory() async {
        await exportHistoryController.refreshExportHistory()
    }

    func retryPendingTranscription(for sessionID: UUID) async {
        let retryContext: PendingTranscriptionRetryContext
        switch transcriptionRecovery.retryContext(
            for: sessionID,
            isRecording: status.phase == .recording,
            provider: settingsStore.aiProvider,
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
        retryTranscriptionStatusPresenter.presentRetryStarted(
            progressMessage: recordingStatusMessages.transcriptionRetryProgressMessage()
        )
        recordingSessionController.swapActivity(reason: "Retrying transcription from preserved audio")
        logPendingTranscriptionRetryRequested(retryContext)

        do {
            guard settingsStore.aiProviderCompatibilityIssue == nil else {
                throw AppError.transcriptionFailure("Finish the AI provider setup in Settings, then retry transcription from this session.")
            }

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

            let pipelineResult = await postTranscriptionPipeline.complete(
                session: updatedSession,
                apiKey: apiKey,
                mode: .retry
            )
            retryPostTranscriptionResultHandler.handle(pipelineResult, context: retryContext)
        } catch {
            pendingTranscriptionRetryFailureHandler.handle(error, context: retryContext)
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
                recordingSessionController.endActivity()
                manualIssueExtractionStatusPresenter.presentFailure(error)
            }

            return
        }

        manualIssueExtractionStatusPresenter.presentPreflightFailure(preflightError, sessionID: transcriptSession.id)
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
            if completion.performedRemoteExport {
                showRevealInFinderToast("Export receipt saved", revealing: ExportReceiptStore.defaultStorageURL)
            }
            await refreshExportHistory()
        } catch {
            recordingSessionController.endActivity()
            issueExportPresentationController.presentFailure(error)
        }
    }

    private func prepareErrorPresentationSideEffects() {
        recordingSessionController.stopTimer(resetElapsed: status.phase == .recording)
        recordingSessionController.endActivity()
        cleanupPendingRecordedAudioIfNeeded()
        issueExtractionController.clearProgress()
        issueExportController.clearProgress()
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
        let hasPendingRecordedAudio = recordingSessionController.pendingRecordedAudioSnapshot != nil
        prepareErrorPresentationSideEffects()
        if !hasPendingRecordedAudio {
            recordingSessionStopFailurePresenter.presentRecordingStopFailure(error)
        } else {
            recordingSessionStopFailurePresenter.presentTranscriptionFailure(error)
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
            prepareErrorPresentationSideEffects()
            recordingSessionStopFailurePresenter.presentPreservationFailure(error)
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
