import CoreGraphics
import Foundation

struct AppBootstrap {
    enum StorageMode: Equatable {
        case production
        case isolatedForTests
    }

    let storageMode: StorageMode
    let settingsStore: SettingsStore
    let transcriptStore: TranscriptStore
    let isolatedDefaultsSuiteName: String?
    let isolatedStorageRootURL: URL?

    init(runtimeEnvironment: AppRuntimeEnvironment, fileManager: FileManager = .default) {
        let launchAtLoginService: any LaunchAtLoginControlling

        if runtimeEnvironment.usesIsolatedRuntime {
            let scope = runtimeEnvironment.testIsolationScope
            let defaultsSuiteName = "BugNarrator.XCTestHost.\(scope)"
            let defaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
            defaults.removePersistentDomain(forName: defaultsSuiteName)

            let storageRootURL = fileManager.temporaryDirectory
                .appendingPathComponent("BugNarrator-XCTestHost-\(scope)", isDirectory: true)
            try? fileManager.removeItem(at: storageRootURL)
            try? fileManager.createDirectory(at: storageRootURL, withIntermediateDirectories: true)

            launchAtLoginService = TestingLaunchAtLoginService(
                status: runtimeEnvironment.testLaunchAtLoginStatus
            )
            self.storageMode = .isolatedForTests
            self.settingsStore = SettingsStore(
                defaults: defaults,
                keychainService: InMemoryKeychainService(),
                launchAtLoginService: launchAtLoginService,
                legacyDefaultsDomains: []
            )
            self.transcriptStore = TranscriptStore(
                fileManager: fileManager,
                storageURL: storageRootURL.appendingPathComponent("sessions.json")
            )
            self.isolatedDefaultsSuiteName = defaultsSuiteName
            self.isolatedStorageRootURL = storageRootURL
            return
        }

        launchAtLoginService = SystemLaunchAtLoginService()
        self.storageMode = .production
        self.settingsStore = SettingsStore(launchAtLoginService: launchAtLoginService)
        self.transcriptStore = TranscriptStore()
        self.isolatedDefaultsSuiteName = nil
        self.isolatedStorageRootURL = nil
    }
}

private final class InMemoryKeychainService: KeychainServicing {
    private var storedValues: [String: String] = [:]

    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String? {
        storedValues[storageKey(service: service, account: account)]
    }

    func setString(_ value: String, service: String, account: String) throws {
        storedValues[storageKey(service: service, account: account)] = value
    }

    func deleteValue(service: String, account: String) throws {
        storedValues.removeValue(forKey: storageKey(service: service, account: account))
    }

    private func storageKey(service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

#if DEBUG
@MainActor
enum UITestRuntimeSupport {
    static func makeAppState(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        runtimeEnvironment: AppRuntimeEnvironment,
        storageRootURL: URL?
    ) -> AppState {
        let rootURL = storageRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-UITestRuntime", isDirectory: true)
        let artifactsRootURL = rootURL.appendingPathComponent("Artifacts", isDirectory: true)

        return AppState(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            audioRecorder: UITestAudioRecorder(storageRootURL: rootURL),
            microphonePermissionService: UITestMicrophonePermissionService(),
            screenCapturePermissionService: UITestScreenCapturePermissionService(),
            transcriptionClient: UITestTranscriptionClient(),
            hotkeyManager: UITestHotkeyManager(),
            screenshotCaptureService: UITestScreenshotCaptureService(),
            screenshotSelectionService: UITestScreenshotSelectionService(),
            issueExtractionService: UITestIssueExtractionService(),
            exportService: UITestIssueExportService(),
            recoveredRecordingImporter: UITestRecoveredRecordingImporter(),
            artifactsService: SessionArtifactsService(rootDirectoryURL: artifactsRootURL),
            clipboardService: UITestClipboardService(),
            urlHandler: UITestURLHandler(),
            runtimeEnvironment: runtimeEnvironment
        )
    }

    static func seedIfNeeded(
        settingsStore: SettingsStore,
        transcriptStore: TranscriptStore,
        runtimeEnvironment: AppRuntimeEnvironment,
        storageRootURL: URL?
    ) {
        guard runtimeEnvironment.shouldSeedSessionLibraryUITestData else {
            return
        }

        settingsStore.apiKey = "sk-ui-test"
        settingsStore.githubToken = "github_pat_ui_test"
        settingsStore.githubRepositoryID = "deffenda/bug-narrator"
        settingsStore.githubRepositoryOwner = "deffenda"
        settingsStore.githubRepositoryName = "bug-narrator"
        settingsStore.githubDefaultLabels = "bug, ui-test"
        settingsStore.jiraBaseURL = "https://example.atlassian.net"
        settingsStore.jiraEmail = "tester@example.com"
        settingsStore.jiraAPIToken = "jira-ui-test-token"
        settingsStore.jiraProjectID = "10001"
        settingsStore.jiraProjectKey = "UCAP"
        settingsStore.jiraIssueTypeID = "10002"
        settingsStore.jiraIssueType = "Task"
        settingsStore.autoExtractIssues = true
        settingsStore.refreshSecretsForUserInitiatedAccess()

        guard transcriptStore.sessions.isEmpty else {
            return
        }

        let rootURL = storageRootURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-UITestFixtures", isDirectory: true)
        let screenshotURL = rootURL
            .appendingPathComponent("Screenshots", isDirectory: true)
            .appendingPathComponent("capture-ui-test-001.png")
        try? FileManager.default.createDirectory(
            at: screenshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? Data("ui-test-screenshot".utf8).write(to: screenshotURL)

        let screenshotID = UUID(uuidString: "00000000-0000-0000-0000-000000000101") ?? UUID()
        let stepID = UUID(uuidString: "00000000-0000-0000-0000-000000000102") ?? UUID()
        let issueID = UUID(uuidString: "00000000-0000-0000-0000-000000000103") ?? UUID()
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000104") ?? UUID()

        let screenshot = SessionScreenshot(
            id: screenshotID,
            elapsedTime: 4,
            filePath: screenshotURL.path
        )
        let issue = ExtractedIssue(
            id: issueID,
            title: "Settings export smoke issue",
            category: .bug,
            severity: .medium,
            component: "Session Library",
            summary: "Export controls should stay available when tracker settings are configured.",
            evidenceExcerpt: "The selected extracted issue can be routed to Jira or GitHub.",
            deduplicationHint: "settings-export-smoke-issue",
            timestamp: 4,
            relatedScreenshotIDs: [screenshotID],
            isSelectedForExport: true,
            sectionTitle: "UI Test",
            reproductionSteps: [
                IssueReproductionStep(
                    id: stepID,
                    instruction: "Open a captured session with extracted issues.",
                    expectedResult: "Per-issue GitHub and Jira targets are editable.",
                    actualResult: "The UI test fixture keeps both export paths configured.",
                    timestamp: 4,
                    screenshotID: screenshotID
                )
            ]
        )
        let session = TranscriptSession(
            id: sessionID,
            createdAt: Date(),
            transcript: "This is a UI smoke transcript for BugNarrator session library export coverage.",
            duration: 12,
            model: "whisper-1",
            languageHint: "en",
            prompt: nil,
            screenshots: [screenshot],
            sections: [],
            issueExtraction: IssueExtractionResult(
                summary: "One export-ready issue is available for UI testing.",
                issues: [issue]
            ),
            artifactsDirectoryPath: rootURL.path
        )

        try? transcriptStore.add(session)
    }
}

@MainActor
private final class UITestAudioRecorder: AudioRecording {
    private let storageRootURL: URL
    private var recordedAudioURL: URL?
    private(set) var currentDuration: TimeInterval = 0

    init(storageRootURL: URL) {
        self.storageRootURL = storageRootURL
    }

    func validateRecordingPrerequisites() async -> AppError? {
        nil
    }

    func validateRecordingActivation() async -> AppError? {
        nil
    }

    func startRecording() async throws {
        currentDuration = 1
        let audioURL = storageRootURL
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("ui-test-recording.m4a")
        try FileManager.default.createDirectory(
            at: audioURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ui-test-audio".utf8).write(to: audioURL)
        recordedAudioURL = audioURL
    }

    func stopRecording() async throws -> RecordedAudio {
        let audioURL = recordedAudioURL ?? storageRootURL
            .appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent("ui-test-recording.m4a")
        if !FileManager.default.fileExists(atPath: audioURL.path) {
            try FileManager.default.createDirectory(
                at: audioURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("ui-test-audio".utf8).write(to: audioURL)
        }

        currentDuration = 12
        return RecordedAudio(fileURL: audioURL, duration: 12)
    }

    func cancelRecording(preserveFile: Bool) async {
        currentDuration = 0
        if !preserveFile, let recordedAudioURL {
            try? FileManager.default.removeItem(at: recordedAudioURL)
        }
    }
}

@MainActor
private final class UITestMicrophonePermissionService: MicrophonePermissionServicing {
    func currentStatus() -> MicrophonePermissionStatus {
        .granted
    }

    func recoveryGuidance(
        for status: MicrophonePermissionStatus,
        runtimeEnvironment: AppRuntimeEnvironment
    ) -> MicrophoneRecoveryGuidance {
        MicrophoneRecoveryGuidance(
            headline: "Microphone available for UI tests.",
            message: "UI tests use a deterministic audio recorder.",
            localTestingNote: nil
        )
    }

    func preflightForRecordingStart(audioRecorder: any AudioRecording) async -> RecordingStartPreflightResult {
        .success
    }
}

@MainActor
private final class UITestScreenCapturePermissionService: ScreenCapturePermissionServicing {
    func currentStatus() -> ScreenCapturePermissionStatus {
        .granted
    }

    func recoveryGuidance(
        for status: ScreenCapturePermissionStatus,
        runtimeEnvironment: AppRuntimeEnvironment
    ) -> ScreenCaptureRecoveryGuidance {
        ScreenCaptureRecoveryGuidance(
            headline: "Screen capture available for UI tests.",
            message: "UI tests use a deterministic screenshot service."
        )
    }

    func preflightForScreenshotCapture(
        screenshotCaptureService: any ScreenshotCapturing,
        hasActiveRecordingSession: Bool
    ) async -> ScreenshotCapturePreflightResult {
        hasActiveRecordingSession ? .success : .blocked(.noActiveSession("Start recording first."))
    }
}

private actor UITestTranscriptionClient: TranscriptionServing {
    func transcribe(fileURL: URL, apiKey: String, request: TranscriptionRequest) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "UI smoke recording transcript. Start recording, capture a screenshot, stop, and review the saved session.",
            segments: [
                TranscriptionSegment(start: 0, end: 12, text: "UI smoke recording transcript.")
            ]
        )
    }

    func validateAPIKey(_ apiKey: String) async throws {}
}

private final class UITestHotkeyManager: HotkeyManaging {
    var onHotKeyPressed: ((HotkeyAction) -> Void)?

    func register(shortcut: HotkeyShortcut, for action: HotkeyAction) {}
    func unregisterAll() {}
}

@MainActor
private final class UITestScreenshotSelectionService: ScreenshotSelecting {
    func selectRegion() async throws -> ScreenshotSelectionResult {
        .selected(CGRect(x: 10, y: 10, width: 120, height: 80))
    }

    func cancelActiveSelection() {}
}

private final class UITestScreenshotCaptureService: ScreenshotCapturing {
    @MainActor
    func validateCaptureAvailability() async -> AppError? {
        nil
    }

    @MainActor
    func captureScreenshot(in rect: CGRect, to url: URL) async throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ui-test-screenshot".utf8).write(to: url)
    }
}

private actor UITestIssueExtractionService: IssueExtracting {
    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String
    ) async throws -> IssueExtractionResult {
        IssueExtractionResult(
            summary: "UI test extraction completed.",
            issues: [
                ExtractedIssue(
                    title: "Recording controls smoke issue",
                    category: .bug,
                    severity: .medium,
                    component: "Recording Controls",
                    summary: "Recording controls completed a safe UI-test session.",
                    evidenceExcerpt: "The deterministic UI test recorder returned a transcript.",
                    timestamp: 1
                )
            ]
        )
    }
}

private actor UITestIssueExportService: IssueExporting {
    func fetchGitHubRepositories(token: String) async throws -> [GitHubRepositoryOption] {
        [
            GitHubRepositoryOption(
                repositoryID: "deffenda/bug-narrator",
                owner: "deffenda",
                name: "bug-narrator",
                description: "BugNarrator"
            ),
            GitHubRepositoryOption(
                repositoryID: "deffenda/new-project-2",
                owner: "deffenda",
                name: "new-project-2",
                description: "New Project 2"
            )
        ]
    }

    func fetchJiraProjects(_ configuration: JiraConnectionConfiguration) async throws -> [JiraProjectOption] {
        [
            JiraProjectOption(projectID: "10001", key: "UCAP", name: "UCAP Teams"),
            JiraProjectOption(projectID: "10002", key: "NP2", name: "New Project 2")
        ]
    }

    func fetchJiraIssueTypes(
        for projectKey: String,
        projectID: String?,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        [
            JiraIssueTypeOption(id: "10002", name: "Task"),
            JiraIssueTypeOption(id: "10003", name: "Bug"),
            JiraIssueTypeOption(id: "10004", name: "Story")
        ]
    }

    func validateGitHubConfiguration(_ configuration: GitHubExportConfiguration) async throws {}

    func validateJiraConfiguration(_ configuration: JiraExportConfiguration) async throws {}

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String
    ) async throws -> IssueExportReview {
        IssueExportReview(
            destination: .github,
            sessionID: session.id,
            items: issues.map { IssueExportReviewItem(issue: $0, matches: []) }
        )
    }

    func prepareJiraExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration,
        apiKey: String,
        model: String
    ) async throws -> IssueExportReview {
        IssueExportReview(
            destination: .jira,
            sessionID: session.id,
            items: issues.map { IssueExportReviewItem(issue: $0, matches: []) }
        )
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        issues.enumerated().map { index, issue in
            ExportResult(
                sourceIssueID: issue.id,
                destination: .github,
                remoteIdentifier: "#\(100 + index)",
                remoteURL: URL(string: "https://github.com/\(configuration.owner)/\(configuration.repository)/issues/\(100 + index)")
            )
        }
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        issues.enumerated().map { index, issue in
            ExportResult(
                sourceIssueID: issue.id,
                destination: .jira,
                remoteIdentifier: "\(configuration.projectKey)-\(200 + index)",
                remoteURL: URL(string: "\(configuration.baseURL.absoluteString)/browse/\(configuration.projectKey)-\(200 + index)")
            )
        }
    }

    func exportHistory() async throws -> [ExportReceipt] {
        []
    }
}

@MainActor
private final class UITestRecoveredRecordingImporter: RecoveredRecordingImporting {
    func importRecoverableRecordings(
        into transcriptStore: TranscriptStore,
        artifactsService: any SessionArtifactsManaging
    ) throws -> Int {
        0
    }
}

private final class UITestClipboardService: ClipboardWriting {
    func copy(_ string: String) {}
}

private final class UITestURLHandler: URLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool {
        true
    }
}
#endif
