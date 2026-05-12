import Foundation

@MainActor
struct AppServiceContainer {
    let audioRecorder: any AudioRecording
    let microphonePermissionService: any MicrophonePermissionServicing
    let screenCapturePermissionService: any ScreenCapturePermissionServicing
    let transcriptionClient: any TranscriptionServing
    let hotkeyManager: any HotkeyManaging
    let screenshotCaptureService: any ScreenshotCapturing
    let screenshotSelectionService: any ScreenshotSelecting
    let issueExtractionService: any IssueExtracting
    let exportService: any IssueExporting
    let recoveredRecordingImporter: any RecoveredRecordingImporting
    let artifactsService: any SessionArtifactsManaging
    let clipboardService: any ClipboardWriting
    let urlHandler: any URLOpening
    let recordingTimer: RecordingTimerViewModel

    static func production(settingsStore: SettingsStore) -> AppServiceContainer {
        AppServiceContainer(
            audioRecorder: RoutingAudioRecorder(settingsStore: settingsStore),
            microphonePermissionService: MicrophonePermissionService(),
            screenCapturePermissionService: ScreenCapturePermissionService(),
            transcriptionClient: TranscriptionClient(),
            hotkeyManager: HotkeyManager(),
            screenshotCaptureService: ScreenshotCaptureService(),
            screenshotSelectionService: ScreenshotSelectionService(),
            issueExtractionService: IssueExtractionService(),
            exportService: ExportService(),
            recoveredRecordingImporter: RecoveredRecordingImporter(),
            artifactsService: SessionArtifactsService(),
            clipboardService: SystemClipboardService(),
            urlHandler: WorkspaceURLHandler(),
            recordingTimer: RecordingTimerViewModel()
        )
    }
}
