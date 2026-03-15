import Foundation
import XCTest
@testable import BugNarrator

@MainActor
final class MockAudioRecorder: AudioRecording {
    var currentDuration: TimeInterval = 0
    var startCallCount = 0
    var stopCallCount = 0
    var cancelPreserveArguments: [Bool] = []
    var startError: Error?
    var stopResults: [Result<RecordedAudio, Error>] = []
    var suspendStop = false
    var permissionState: MicrophonePermissionState = .authorized

    private var stopContinuation: CheckedContinuation<RecordedAudio, Error>?

    func microphonePermissionState() -> MicrophonePermissionState {
        permissionState
    }

    func startRecording() async throws {
        startCallCount += 1

        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws -> RecordedAudio {
        stopCallCount += 1

        if suspendStop {
            return try await withCheckedThrowingContinuation { continuation in
                stopContinuation = continuation
            }
        }

        guard !stopResults.isEmpty else {
            throw AppError.recordingFailure("No mock stop result was configured.")
        }

        return try stopResults.removeFirst().get()
    }

    func cancelRecording(preserveFile: Bool) async {
        cancelPreserveArguments.append(preserveFile)
    }

    func resumeStop(with result: Result<RecordedAudio, Error>) {
        let continuation = stopContinuation
        stopContinuation = nil
        suspendStop = false

        switch result {
        case .success(let recordedAudio):
            continuation?.resume(returning: recordedAudio)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

actor MockTranscriptionClient: TranscriptionServing {
    private var queuedResults: [Result<TranscriptionResult, Error>] = []
    private var validationResults: [Result<Void, Error>] = []
    private(set) var callCount = 0
    private(set) var requestedFileURLs: [URL] = []
    private(set) var requestedModels: [String] = []
    private(set) var validationCallCount = 0

    func enqueue(_ result: Result<TranscriptionResult, Error>) {
        queuedResults.append(result)
    }

    func enqueueValidation(_ result: Result<Void, Error>) {
        validationResults.append(result)
    }

    func transcribe(fileURL: URL, apiKey: String, request: TranscriptionRequest) async throws -> TranscriptionResult {
        callCount += 1
        requestedFileURLs.append(fileURL)
        requestedModels.append(request.model)

        guard !queuedResults.isEmpty else {
            throw AppError.transcriptionFailure("No mock transcription result was configured.")
        }

        return try queuedResults.removeFirst().get()
    }

    func validateAPIKey(_ apiKey: String) async throws {
        validationCallCount += 1

        if validationResults.isEmpty {
            return
        }

        try validationResults.removeFirst().get()
    }
}

final class MockHotkeyManager: HotkeyManaging {
    var onHotKeyPressed: ((HotkeyAction) -> Void)?
    private(set) var registeredShortcuts: [HotkeyAction: HotkeyShortcut] = [:]

    func register(shortcut: HotkeyShortcut, for action: HotkeyAction) {
        registeredShortcuts[action] = shortcut
    }

    func unregisterAll() {
        registeredShortcuts.removeAll()
    }
}

final class MockScreenshotCaptureService: ScreenshotCapturing {
    var error: Error?
    var delayNanoseconds: UInt64 = 0
    var onCaptureStart: (() -> Void)?

    init(error: Error? = nil, delayNanoseconds: UInt64 = 0, onCaptureStart: (() -> Void)? = nil) {
        self.error = error
        self.delayNanoseconds = delayNanoseconds
        self.onCaptureStart = onCaptureStart
    }

    @MainActor
    func captureScreenshot(to url: URL) async throws {
        if let error {
            throw error
        }

        onCaptureStart?()

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        try Data("screenshot".utf8).write(to: url)
    }
}

actor MockIssueExtractionService: IssueExtracting {
    var result = IssueExtractionResult(summary: "", issues: [])

    func setResult(_ result: IssueExtractionResult) {
        self.result = result
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String
    ) async throws -> IssueExtractionResult {
        result
    }
}

actor MockExportService: IssueExporting {
    var gitHubResults: [ExportResult] = []
    var jiraResults: [ExportResult] = []
    var gitHubError: Error?
    var jiraError: Error?

    private(set) var gitHubCallCount = 0
    private(set) var jiraCallCount = 0

    func setGitHubResults(_ results: [ExportResult]) {
        gitHubResults = results
    }

    func setJiraResults(_ results: [ExportResult]) {
        jiraResults = results
    }

    func setGitHubError(_ error: Error?) {
        gitHubError = error
    }

    func setJiraError(_ error: Error?) {
        jiraError = error
    }

    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        gitHubCallCount += 1

        if let gitHubError {
            throw gitHubError
        }

        return gitHubResults
    }

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult] {
        jiraCallCount += 1

        if let jiraError {
            throw jiraError
        }

        return jiraResults
    }
}

final class MockArtifactsService: SessionArtifactsManaging {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL

    private(set) var createdDirectories: [URL] = []
    private(set) var removedDirectories: [URL] = []

    init(rootDirectoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootDirectoryURL = rootDirectoryURL
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }

    func createArtifactsDirectory(for sessionID: UUID) throws -> URL {
        let directoryURL = rootDirectoryURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        createdDirectories.append(directoryURL)
        return directoryURL
    }

    func makeScreenshotURL(
        in directoryURL: URL,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval
    ) -> URL {
        directoryURL.appendingPathComponent("\(prefix)-\(index)").appendingPathExtension("png")
    }

    func removeArtifactsDirectory(at directoryURL: URL) {
        removedDirectories.append(directoryURL)
        try? fileManager.removeItem(at: directoryURL)
    }
}

final class MockClipboardService: ClipboardWriting {
    private(set) var copiedStrings: [String] = []

    func copy(_ string: String) {
        copiedStrings.append(string)
    }
}

final class MockURLHandler: URLOpening {
    private(set) var openedURLs: [URL] = []
    var shouldSucceed = true
    var openResults: [Bool] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        if !openResults.isEmpty {
            return openResults.removeFirst()
        }

        return shouldSucceed
    }
}

final class MockKeychainService: KeychainServicing {
    var values: [String: String] = [:]
    var setError: Error?
    var interactionRequiredKeys: Set<String> = []
    private(set) var readRequests: [(service: String, account: String, allowInteraction: Bool)] = []

    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String? {
        readRequests.append((service: service, account: account, allowInteraction: allowInteraction))

        let key = key(forService: service, account: account)
        if interactionRequiredKeys.contains(key), !allowInteraction {
            return nil
        }

        return values[key]
    }

    func setString(_ value: String, service: String, account: String) throws {
        if let setError {
            throw setError
        }

        values[key(forService: service, account: account)] = value
    }

    func deleteValue(service: String, account: String) throws {
        values.removeValue(forKey: key(forService: service, account: account))
    }

    private func key(forService service: String, account: String) -> String {
        "\(service)::\(account)"
    }
}

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
    let issueExtractionService: MockIssueExtractionService
    let exportService: MockExportService
    let appState: AppState

    init(
        apiKey: String = "test-api-key",
        debugMode: Bool = false,
        autoCopyTranscript: Bool = true,
        autoSaveTranscript: Bool = true,
        autoExtractIssues: Bool = false,
        screenshotCaptureService: MockScreenshotCaptureService = MockScreenshotCaptureService()
    ) {
        let fileManager = FileManager.default
        let rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorTests-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let defaultsSuiteName = "BugNarratorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        let keychainService = MockKeychainService()
        let settingsStore = SettingsStore(defaults: defaults, keychainService: keychainService)
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
        self.issueExtractionService = issueExtractionService
        self.exportService = exportService
        self.appState = AppState(
            settingsStore: settingsStore,
            transcriptStore: transcriptStore,
            audioRecorder: audioRecorder,
            transcriptionClient: transcriptionClient,
            hotkeyManager: hotkeyManager,
            screenshotCaptureService: screenshotCaptureService,
            issueExtractionService: issueExtractionService,
            exportService: exportService,
            artifactsService: artifactsService,
            clipboardService: clipboardService,
            urlHandler: urlHandler
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

func makeSampleTranscriptSession(index: Int) -> TranscriptSession {
    TranscriptSession(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(index * 60)),
        transcript: "Transcript \(index)",
        duration: TimeInterval(index),
        model: "whisper-1",
        languageHint: nil,
        prompt: nil
    )
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }

        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
            fatalError("MockURLProtocol.requestHandler was not set.")
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

func makeMockURLSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}
