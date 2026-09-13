import Foundation

/// Constructs the application controller graph while `AppState` remains the
/// user-facing orchestration and observation boundary.
@MainActor
final class AppStateRuntimeGraph {
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
    let recordingWorkInProgress: () -> Bool
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
    let transcriptionClient: any TranscriptionServing
    let hotkeyManager: any HotkeyManaging
    let hotkeySettingsBinder: HotkeySettingsBinder
    let objectChangeForwarder: ObservableObjectChangeForwarder
    let lifecycleNotificationBinder: AppLifecycleNotificationBinder
    let launchDiagnosticsReporter: AppLaunchDiagnosticsReporter
    let artifactsService: any SessionArtifactsManaging

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
        let transcriptionLogger = DiagnosticsLogger(category: .transcription)
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.localTranscriptionManager = localTranscriptionManager ?? (runtimeEnvironment.usesIsolatedRuntime
            ? .isolated(directory: FileManager.default.temporaryDirectory.appendingPathComponent("BugNarrator-LocalServer-\(UUID())", isDirectory: true))
            : LocalTranscriptionManager())
        self.recordingTimer = recordingTimer
        let presentationState = AppPresentationState()
        self.presentationState = presentationState
        errorPresenter = AppErrorPresenter(
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
        recordingSessionStopReadinessPresenter = RecordingSessionStopReadinessPresenter(
            errorPresenter: errorPresenter
        )
        recordingSessionCancelStatusPresenter = RecordingSessionCancelStatusPresenter(
            setStatus: { status in presentationState.setStatus(status, error: nil) }
        )
        let recordingStatusMessages = RecordingStatusMessageProvider {
            RecordingStatusMessageSnapshot(
                audioSource: settingsStore.recordingAudioSource,
                aiProvider: settingsStore.aiProvider,
                hasUsableAIProviderCredential: settingsStore.hasUsableAIProviderCredential,
                aiProviderCompatibilityIssue: settingsStore.aiProviderCompatibilityIssue,
                autoExtractIssues: settingsStore.autoExtractIssues,
                autoCopyTranscript: settingsStore.autoCopyTranscript
            )
        }
        self.recordingStatusMessages = recordingStatusMessages
        recordingSessionStartStatusPresenter = RecordingSessionStartStatusPresenter(
            errorPresenter: errorPresenter,
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
        sessionLibraryStatusPresenter = SessionLibraryStatusPresenter(
            errorPresenter: errorPresenter
        )
        exportHistoryController = ExportHistoryController(exportService: exportService)
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
        permissionRecoveryStatusPresenter = PermissionRecoveryStatusPresenter(
            errorPresenter: errorPresenter
        )
        launchDiagnosticsReporter = AppLaunchDiagnosticsReporter(
            permissionRecoveryController: permissionRecoveryController,
            transcriptStore: transcriptStore
        )
        let appUtilityActions = AppUtilityActionController(
            urlHandler: urlHandler,
            permissionRecoveryController: permissionRecoveryController
        )
        self.appUtilityActions = appUtilityActions
        recordingSessionStopFailurePresenter = RecordingSessionStopFailurePresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        postTranscriptionStatusPresenter = PostTranscriptionStatusPresenter(
            recordingStatusMessages: recordingStatusMessages,
            setStatus: { status in presentationState.setStatus(status, error: nil) },
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        postTranscriptionFailurePresenter = PostTranscriptionFailurePresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        postTranscriptionPipeline = PostTranscriptionPipelineController(
            settingsStore: settingsStore,
            sessionLibrary: sessionLibrary,
            issueExtractionController: issueExtractionController,
            recordingSessionController: recordingSessionController,
            statusPresenter: postTranscriptionStatusPresenter,
            telemetryRecorder: telemetryRecorder,
            transcriptionLogger: transcriptionLogger
        )
        manualIssueExtractionStatusPresenter = ManualIssueExtractionStatusPresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        issueExtractionFailurePresenter = IssueExtractionFailurePresenter(
            errorPresenter: errorPresenter
        )
        issueExportPresentationController = IssueExportPresentationController(
            errorPresenter: errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() }
        )
        transcriptPersistenceFailurePresenter = TranscriptPersistenceFailurePresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        let appUtilityActionPresenter = AppUtilityActionResultPresenter(
            statusPhase: { presentationState.status.phase },
            setStatus: { status in
                presentationState.setStatus(status, error: nil)
            }
        )
        self.appUtilityActionPresenter = appUtilityActionPresenter
        finishedRecordingPostTranscriptionResultHandler = FinishedRecordingPostTranscriptionResultHandler(
            sessionLibrary: sessionLibrary,
            recordingSessionController: recordingSessionController,
            statusPresenter: postTranscriptionStatusPresenter,
            transcriptPersistenceFailurePresenter: transcriptPersistenceFailurePresenter,
            postTranscriptionFailurePresenter: postTranscriptionFailurePresenter,
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
        supportDataActionPresenter = SupportDataActionPresenter(
            presentationState: presentationState,
            errorPresenter: errorPresenter,
            utilityActions: appUtilityActions,
            utilityResultPresenter: appUtilityActionPresenter
        )
        supportDataController = SupportDataController(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            exportService: exportService,
            clipboardService: clipboardService,
            debugBundleExporter: debugBundleExporter,
            privacyDataExporter: privacyDataExporter,
            telemetryRecorder: telemetryRecorder,
            localPrivacyDataManager: localPrivacyDataManager
        )
        localDataDeletionController = LocalDataDeletionController(
            transcriptStore: transcriptStore,
            sessionLibrary: sessionLibrary,
            supportDataController: supportDataController,
            exportHistoryController: exportHistoryController
        )
        let transcriptionRecovery = TranscriptionRecoveryController(
            sessionLibrary: sessionLibrary,
            artifactsService: artifactsService
        )
        self.transcriptionRecovery = transcriptionRecovery
        retryTranscriptionStatusPresenter = RetryTranscriptionStatusPresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() },
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() }
        )
        pendingTranscriptionRetryFailureHandler = PendingTranscriptionRetryFailureHandler(
            transcriptionRecovery: transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            retryStatusPresenter: retryTranscriptionStatusPresenter,
            provider: { settingsStore.aiProvider }
        )
        retryableSessionPreservationPresenter = RetryableSessionPreservationPresenter(
            errorPresenter: errorPresenter,
            showTranscriptWindow: { appUtilityActions.showTranscriptWindow?() },
            showSettingsWindow: { appUtilityActions.showSettingsWindow?() },
            provider: { settingsStore.aiProvider }
        )
        retryPostTranscriptionResultHandler = RetryPostTranscriptionResultHandler(
            transcriptionRecovery: transcriptionRecovery,
            recordingSessionController: recordingSessionController,
            statusPresenter: postTranscriptionStatusPresenter,
            sessionLibraryStatusPresenter: sessionLibraryStatusPresenter,
            postTranscriptionFailurePresenter: postTranscriptionFailurePresenter,
            debugMode: { settingsStore.debugMode }
        )
        let screenshotCoordinator = ScreenshotCoordinator(
            screenCapturePermissionService: screenCapturePermissionService,
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: screenshotSelectionService,
            artifactsService: artifactsService
        )
        self.screenshotCoordinator = screenshotCoordinator
        screenshotCaptureController = ScreenshotCaptureController(
            screenshotCoordinator: screenshotCoordinator,
            recordingSessionController: recordingSessionController,
            errorPresenter: errorPresenter,
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
        hotkeySettingsBinder = HotkeySettingsBinder(hotkeyManager: hotkeyManager)
        objectChangeForwarder = ObservableObjectChangeForwarder()
        lifecycleNotificationBinder = AppLifecycleNotificationBinder()
        self.artifactsService = artifactsService
        trackerIntegration = TrackerIntegrationController(
            settingsStore: settingsStore,
            exportService: exportService
        )
        aiProviderSettings = AIProviderSettingsController(
            settingsStore: settingsStore,
            transcriptionClient: transcriptionClient
        )
        let recordingWorkInProgress = {
            transcriptionRecovery.retryingSessionID != nil || recordingSessionController.hasInFlightRecordingWork(statusPhase: presentationState.status.phase)
        }
        self.recordingWorkInProgress = recordingWorkInProgress
        let applicationTerminationController = ApplicationTerminationController(
            isRecordingInProgress: recordingWorkInProgress,
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
    }
}
