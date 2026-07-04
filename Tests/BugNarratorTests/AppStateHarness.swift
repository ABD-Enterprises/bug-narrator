import Foundation
@testable import BugNarrator

@MainActor
struct AppStateHarness {
    let rootDirectoryURL: URL
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let keychainService: MockKeychainService
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let audioRecorder: MockAudioRecorder
    let transcriptionClient: MockTranscriptionClient
    let hotkeyManager: MockHotkeyManager
    let artifactsService: MockArtifactsService
    let clipboardService: MockClipboardService
    let urlHandler: MockURLHandler
    let debugBundleExporter: MockDebugBundleExporter
    let privacyDataExporter: MockPrivacyDataExporter
    let telemetryRecorder: MockOperationalTelemetryRecorder
    let localPrivacyDataManager: MockLocalPrivacyDataManager
    let issueExtractionService: MockIssueExtractionService
    let exportService: MockExportService
    let screenCapturePermissionAccess: MockScreenCapturePermissionAccess
    let screenshotSelectionService: MockScreenshotSelectionService
    let appState: AppState

    init(
        apiKey: String = "test-api-key",
        debugMode: Bool = false,
        autoCopyTranscript: Bool = true,
        autoSaveTranscript: Bool = true,
        autoExtractIssues: Bool = false,
        launchAtLoginStatus: LaunchAtLoginStatus = .disabled,
        screenshotCaptureService: MockScreenshotCaptureService = MockScreenshotCaptureService(),
        screenshotSelectionService: MockScreenshotSelectionService = MockScreenshotSelectionService(),
        debugBundleExporter: MockDebugBundleExporter = MockDebugBundleExporter(),
        privacyDataExporter: MockPrivacyDataExporter = MockPrivacyDataExporter(),
        telemetryRecorder: MockOperationalTelemetryRecorder = MockOperationalTelemetryRecorder(),
        localPrivacyDataManager: MockLocalPrivacyDataManager = MockLocalPrivacyDataManager(),
        runtimeEnvironment: AppRuntimeEnvironment = AppRuntimeEnvironment(bundlePath: "/Applications/BugNarrator.app")
    ) {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let defaultsSuiteName = "BugNarratorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let keychainService = MockKeychainService()
        let launchAtLoginService = MockLaunchAtLoginService(status: launchAtLoginStatus)
        let settingsStore = SettingsStore(
            defaults: defaults,
            keychainService: keychainService,
            launchAtLoginService: launchAtLoginService
        )
        settingsStore.apiKey = apiKey
        settingsStore.debugMode = debugMode
        settingsStore.autoCopyTranscript = autoCopyTranscript
        settingsStore.autoSaveTranscript = autoSaveTranscript
        settingsStore.autoExtractIssues = autoExtractIssues

        let transcriptStore = TranscriptStore(
            fileManager: fileManager,
            storageURL: rootDirectoryURL.appendingPathComponent("sessions.json")
        )
        let audioRecorder = MockAudioRecorder()
        let transcriptionClient = MockTranscriptionClient()
        let hotkeyManager = MockHotkeyManager()
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let clipboardService = MockClipboardService()
        let urlHandler = MockURLHandler()
        let issueExtractionService = MockIssueExtractionService()
        let exportService = MockExportService()
        let screenCapturePermissionAccess = MockScreenCapturePermissionAccess()

        self.rootDirectoryURL = rootDirectoryURL
        self.defaultsSuiteName = defaultsSuiteName
        self.defaults = defaults
        self.keychainService = keychainService
        self.settingsStore = settingsStore
        self.transcriptStore = transcriptStore
        self.audioRecorder = audioRecorder
        self.transcriptionClient = transcriptionClient
        self.hotkeyManager = hotkeyManager
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.urlHandler = urlHandler
        self.debugBundleExporter = debugBundleExporter
        self.privacyDataExporter = privacyDataExporter
        self.telemetryRecorder = telemetryRecorder
        self.localPrivacyDataManager = localPrivacyDataManager
        self.issueExtractionService = issueExtractionService
        self.exportService = exportService
        self.screenCapturePermissionAccess = screenCapturePermissionAccess
        self.screenshotSelectionService = screenshotSelectionService
        self.appState = AppState(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            screenCapturePermissionService: ScreenCapturePermissionService(permissionAccess: screenCapturePermissionAccess),
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
            recordingTimer: RecordingTimerViewModel(),
            runtimeEnvironment: runtimeEnvironment
        )
    }

    func makeRecordedAudio(
        fileName: String = UUID().uuidString,
        contents: String = "audio",
        duration: TimeInterval = 4
    ) throws -> RecordedAudio {
        let fileURL = rootDirectoryURL.appendingPathComponent(fileName).appendingPathExtension("m4a")
        try Data(contents.utf8).write(to: fileURL)
        return RecordedAudio(fileURL: fileURL, duration: duration)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

