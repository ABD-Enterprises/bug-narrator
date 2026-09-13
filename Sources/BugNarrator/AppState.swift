import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var showDiscardConfirmation = false
    @Published var isPresentingSystemAudioExplainer = false
    private var systemAudioExplainerAcknowledged = false

    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let localTranscriptionManager: LocalTranscriptionManager
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
    private let recordingWorkInProgress: () -> Bool
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

    var retryingSessionID: UUID? {
        transcriptionRecovery.retryingSessionID
    }

    convenience init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment(),
        localTranscriptionManager: LocalTranscriptionManager? = nil
    ) {
        self.init(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            services: .production(settingsStore: settingsStore),
            runtimeEnvironment: runtimeEnvironment,
            localTranscriptionManager: localTranscriptionManager
        )
    }

    convenience init(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        services: AppServiceContainer,
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment(),
        localTranscriptionManager: LocalTranscriptionManager? = nil
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
            runtimeEnvironment: runtimeEnvironment,
            localTranscriptionManager: localTranscriptionManager
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
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment(),
        localTranscriptionManager: LocalTranscriptionManager? = nil
    ) {
        let graph = AppStateRuntimeGraph(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            audioRecorder: audioRecorder,
            microphonePermissionService: microphonePermissionService,
            screenCapturePermissionService: screenCapturePermissionService,
            transcriptionClient: transcriptionClient,
            hotkeyManager: hotkeyManager,
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: screenshotSelectionService,
            issueExtractionService: issueExtractionService,
            exportService: exportService,
            artifactsService: artifactsService,
            clipboardService: clipboardService,
            urlHandler: urlHandler,
            debugBundleExporter: debugBundleExporter,
            privacyDataExporter: privacyDataExporter,
            telemetryRecorder: telemetryRecorder,
            localPrivacyDataManager: localPrivacyDataManager,
            recordingTimer: recordingTimer,
            runtimeEnvironment: runtimeEnvironment,
            localTranscriptionManager: localTranscriptionManager
        )
        self.settingsStore = graph.settingsStore
        self.transcriptStore = graph.transcriptStore
        self.localTranscriptionManager = graph.localTranscriptionManager
        self.trackerIntegration = graph.trackerIntegration
        self.aiProviderSettings = graph.aiProviderSettings
        self.recordingTimer = graph.recordingTimer
        self.presentationState = graph.presentationState
        self.errorPresenter = graph.errorPresenter
        self.transcriptPersistenceFailurePresenter = graph.transcriptPersistenceFailurePresenter
        self.postTranscriptionFailurePresenter = graph.postTranscriptionFailurePresenter
        self.transientToastController = graph.transientToastController
        self.recordingSessionController = graph.recordingSessionController
        self.recordingSessionStartStatusPresenter = graph.recordingSessionStartStatusPresenter
        self.recordingSessionStopReadinessPresenter = graph.recordingSessionStopReadinessPresenter
        self.recordingSessionStopFailurePresenter = graph.recordingSessionStopFailurePresenter
        self.recordingSessionCancelStatusPresenter = graph.recordingSessionCancelStatusPresenter
        self.recordingStatusMessages = graph.recordingStatusMessages
        self.postTranscriptionStatusPresenter = graph.postTranscriptionStatusPresenter
        self.postTranscriptionPipeline = graph.postTranscriptionPipeline
        self.finishedRecordingPostTranscriptionResultHandler = graph.finishedRecordingPostTranscriptionResultHandler
        self.retryPostTranscriptionResultHandler = graph.retryPostTranscriptionResultHandler
        self.sessionLibrary = graph.sessionLibrary
        self.sessionLibraryStatusPresenter = graph.sessionLibraryStatusPresenter
        self.exportHistoryController = graph.exportHistoryController
        self.issueExtractionController = graph.issueExtractionController
        self.manualIssueExtractionStatusPresenter = graph.manualIssueExtractionStatusPresenter
        self.issueExtractionFailurePresenter = graph.issueExtractionFailurePresenter
        self.issueExportController = graph.issueExportController
        self.issueExportPresentationController = graph.issueExportPresentationController
        self.permissionRecoveryController = graph.permissionRecoveryController
        self.permissionRecoveryStatusPresenter = graph.permissionRecoveryStatusPresenter
        self.appUtilityActions = graph.appUtilityActions
        self.appUtilityActionPresenter = graph.appUtilityActionPresenter
        self.recordingWorkInProgress = graph.recordingWorkInProgress
        self.applicationTerminationController = graph.applicationTerminationController
        self.supportDataController = graph.supportDataController
        self.supportDataActionPresenter = graph.supportDataActionPresenter
        self.localDataDeletionController = graph.localDataDeletionController
        self.transcriptionRecovery = graph.transcriptionRecovery
        self.retryTranscriptionStatusPresenter = graph.retryTranscriptionStatusPresenter
        self.pendingTranscriptionRetryFailureHandler = graph.pendingTranscriptionRetryFailureHandler
        self.retryableSessionPreservationPresenter = graph.retryableSessionPreservationPresenter
        self.screenshotCoordinator = graph.screenshotCoordinator
        self.screenshotCaptureController = graph.screenshotCaptureController
        self.transcriptionClient = graph.transcriptionClient
        self.hotkeyManager = graph.hotkeyManager
        self.hotkeySettingsBinder = graph.hotkeySettingsBinder
        self.objectChangeForwarder = graph.objectChangeForwarder
        self.lifecycleNotificationBinder = graph.lifecycleNotificationBinder
        self.launchDiagnosticsReporter = graph.launchDiagnosticsReporter
        self.artifactsService = graph.artifactsService

        let presentationState = graph.presentationState
        let recordingSessionController = graph.recordingSessionController
        let recordingSessionStartStatusPresenter = graph.recordingSessionStartStatusPresenter
        let sessionLibrary = graph.sessionLibrary
        let exportHistoryController = graph.exportHistoryController
        let issueExtractionController = graph.issueExtractionController
        let issueExtractionFailurePresenter = graph.issueExtractionFailurePresenter
        let issueExportController = graph.issueExportController
        let permissionRecoveryController = graph.permissionRecoveryController
        let transcriptionRecovery = graph.transcriptionRecovery
        let screenshotCoordinator = graph.screenshotCoordinator
        let trackerIntegration = graph.trackerIntegration
        let aiProviderSettings = graph.aiProviderSettings
        let applicationTerminationController = graph.applicationTerminationController
        let objectChangeForwarder = graph.objectChangeForwarder
        let lifecycleNotificationBinder = graph.lifecycleNotificationBinder
        let hotkeySettingsBinder = graph.hotkeySettingsBinder
        let launchDiagnosticsReporter = graph.launchDiagnosticsReporter

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
                trackerIntegration.jira.objectWillChange,
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

    var activeTimelineMomentCount: Int {
        activeRecordingSession?.markers.count ?? 0
    }

    var activeScreenshotCount: Int {
        activeRecordingSession?.screenshots.count ?? 0
    }

    func isActiveRecordingSession(_ sessionID: UUID) -> Bool {
        status.phase == .recording && activeRecordingSession?.sessionID == sessionID
    }

    var needsAPIKeySetup: Bool {
        settingsStore.aiProviderCompatibilityIssue != nil ||
            (settingsStore.aiProvider.requiresAPIKey && !settingsStore.hasUsableAIProviderCredential)
    }

    var preferredRecordingWorkflowSummary: String {
        "Open the recording controls window or use the global hotkeys while you keep testing."
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
    var localServerControlsDisabled: Bool {
        recordingSessionController.terminationPending || recordingWorkInProgress()
    }

    func stopLocalServer(_ manager: LocalTranscriptionManager) {
        guard !localServerControlsDisabled else { return }
        manager.stop()
    }

    func removeLocalServer(_ manager: LocalTranscriptionManager) {
        guard !localServerControlsDisabled else { return }
        manager.remove()
    }

    func setTerminationPending(_ pending: Bool) {
        recordingSessionController.setTerminationPending(pending)
    }

    func startSession() async {
        guard !recordingSessionController.terminationPending, transcriptionRecovery.retryingSessionID == nil else { return }
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
            recordingSessionController.swapActivity(reason: "Transcribing recorded audio")

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
    /// Whether the What's New sheet would auto-present, without presenting it.
    /// Lets the launch path pick between this and the first-run tour rather
    /// than firing both (#357).
    func shouldAutoShowChangelogOnLaunch(metadata: BugNarratorMetadata = BugNarratorMetadata()) -> Bool {
        settingsStore.shouldAutoShowChangelog(
            currentVersion: metadata.version,
            hasExistingUserState: !transcriptStore.libraryEntries.isEmpty
        )
    }

    func presentChangelogIfNeeded(metadata: BugNarratorMetadata = BugNarratorMetadata()) {
        // `libraryEntries`, not `sessions`: a partitioned store loads session
        // bodies lazily, so `sessions` is empty on a cold launch however much
        // history exists. Reading it here told an established user they were
        // brand new, which both suppressed their changelog and — once #357
        // landed — offered them a first-run tour (found in review of #357).
        let hasExistingUserState = !transcriptStore.libraryEntries.isEmpty
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

    func retryPendingTranscription(for sessionID: UUID) async {
        guard !localServerControlsDisabled else { return }
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
                    includeScreenshots: settingsStore.uploadScreenshotsForExtraction,
                    capabilities: .forProvider(settingsStore.aiProvider),
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
        if let failureReason = transcriptionRecovery.preservableStopFailureReason(for: error),
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
}
