import Foundation
import XCTest
@testable import BugNarrator

@MainActor
final class MockAudioRecorder: AudioRecording, MicrophonePermissionAccessing {
    enum ActivationProbeBehavior {
        case automatic
        case success
        case error(AppError)
    }

    var currentDuration: TimeInterval = 0
    var startCallCount = 0
    var stopCallCount = 0
    var cancelPreserveArguments: [Bool] = []
    var startError: Error?
    var stopResults: [Result<RecordedAudio, Error>] = []
    var suspendStop = false
    var permissionState: MicrophonePermissionState = .authorized
    var requestedPermissionStates: [MicrophonePermissionState] = []
    var prerequisiteError: AppError?
    var activationProbeBehavior: ActivationProbeBehavior = .automatic
    private(set) var permissionRequestCallCount = 0
    private(set) var activationProbeCallCount = 0

    private var stopContinuation: CheckedContinuation<RecordedAudio, Error>?

    func currentPermissionState() -> MicrophonePermissionState {
        permissionState
    }

    func requestPermissionIfNeeded() async -> MicrophonePermissionState {
        permissionRequestCallCount += 1

        if !requestedPermissionStates.isEmpty {
            permissionState = requestedPermissionStates.removeFirst()
        }

        return permissionState
    }

    func validateRecordingPrerequisites() async -> AppError? {
        prerequisiteError
    }

    func validateRecordingActivation() async -> AppError? {
        activationProbeCallCount += 1

        switch activationProbeBehavior {
        case .automatic:
            if let prerequisiteError {
                return prerequisiteError
            }

            switch permissionState {
            case .authorized, .notDetermined:
                return nil
            case .denied:
                return .microphonePermissionDenied
            case .restricted:
                return .microphonePermissionRestricted
            }
        case .success:
            return nil
        case .error(let error):
            return error
        }
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
    var availabilityError: AppError?
    var delayNanoseconds: UInt64 = 0
    var onCaptureStart: (() -> Void)?
    private(set) var capturedRects: [CGRect] = []

    init(error: Error? = nil, delayNanoseconds: UInt64 = 0, onCaptureStart: (() -> Void)? = nil) {
        self.error = error
        self.delayNanoseconds = delayNanoseconds
        self.onCaptureStart = onCaptureStart
    }

    @MainActor
    func validateCaptureAvailability() async -> AppError? {
        availabilityError
    }

    @MainActor
    func captureScreenshot(in rect: CGRect, to url: URL) async throws {
        if let error {
            throw error
        }

        capturedRects.append(rect)
        onCaptureStart?()

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        try Data("screenshot".utf8).write(to: url)
    }
}

@MainActor
final class MockScreenshotSelectionService: ScreenshotSelecting {
    var nextResult: ScreenshotSelectionResult = .selected(CGRect(x: 20, y: 20, width: 120, height: 80))
    var error: Error?
    private(set) var selectRegionCallCount = 0

    func selectRegion() async throws -> ScreenshotSelectionResult {
        selectRegionCallCount += 1

        if let error {
            throw error
        }

        return nextResult
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
    var gitHubReview: IssueExportReview?
    var jiraReview: IssueExportReview?
    var gitHubError: Error?
    var jiraError: Error?
    var gitHubRepositories: [GitHubRepositoryOption] = []
    var jiraProjects: [JiraProjectOption] = []
    var jiraIssueTypesByProjectKey: [String: [JiraIssueTypeOption]] = [:]
    var suspendJiraIssueTypeFetch = false

    private(set) var gitHubCallCount = 0
    private(set) var jiraCallCount = 0
    private(set) var gitHubReviewCallCount = 0
    private(set) var jiraReviewCallCount = 0
    private(set) var gitHubValidationCallCount = 0
    private(set) var jiraValidationCallCount = 0
    private(set) var gitHubRepositoryFetchCallCount = 0
    private(set) var jiraProjectFetchCallCount = 0
    private(set) var jiraIssueTypeFetchCallCount = 0
    private(set) var lastGitHubIssues: [ExtractedIssue] = []
    private(set) var lastJiraIssues: [ExtractedIssue] = []
    private var gitHubValidationError: Error?
    private var jiraValidationError: Error?
    private var gitHubRepositoriesError: Error?
    private var jiraProjectsError: Error?
    private var jiraIssueTypesError: Error?
    private var jiraIssueTypeFetchContinuations: [(projectKey: String, continuation: CheckedContinuation<[JiraIssueTypeOption], Error>)] = []

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

    func setGitHubReview(_ review: IssueExportReview) {
        gitHubReview = review
    }

    func setJiraReview(_ review: IssueExportReview) {
        jiraReview = review
    }

    func setGitHubValidationError(_ error: Error?) {
        gitHubValidationError = error
    }

    func setJiraValidationError(_ error: Error?) {
        jiraValidationError = error
    }

    func setGitHubRepositories(_ repositories: [GitHubRepositoryOption]) {
        gitHubRepositories = repositories
    }

    func setGitHubRepositoriesError(_ error: Error?) {
        gitHubRepositoriesError = error
    }

    func setJiraProjects(_ projects: [JiraProjectOption]) {
        jiraProjects = projects
    }

    func setJiraIssueTypes(_ issueTypes: [JiraIssueTypeOption], for projectKey: String) {
        jiraIssueTypesByProjectKey[projectKey] = issueTypes
    }

    func setJiraProjectsError(_ error: Error?) {
        jiraProjectsError = error
    }

    func setJiraIssueTypesError(_ error: Error?) {
        jiraIssueTypesError = error
    }

    func setSuspendJiraIssueTypeFetch(_ shouldSuspend: Bool) {
        suspendJiraIssueTypeFetch = shouldSuspend
    }

    func fetchGitHubRepositories(
        token: String
    ) async throws -> [GitHubRepositoryOption] {
        gitHubRepositoryFetchCallCount += 1

        if let gitHubRepositoriesError {
            throw gitHubRepositoriesError
        }

        return gitHubRepositories
    }

    func fetchJiraProjects(
        _ configuration: JiraConnectionConfiguration
    ) async throws -> [JiraProjectOption] {
        jiraProjectFetchCallCount += 1

        if let jiraProjectsError {
            throw jiraProjectsError
        }

        return jiraProjects
    }

    func fetchJiraIssueTypes(
        for projectKey: String,
        configuration: JiraConnectionConfiguration
    ) async throws -> [JiraIssueTypeOption] {
        jiraIssueTypeFetchCallCount += 1

        if suspendJiraIssueTypeFetch {
            return try await withCheckedThrowingContinuation { continuation in
                jiraIssueTypeFetchContinuations.append((projectKey: projectKey, continuation: continuation))
            }
        }

        if let jiraIssueTypesError {
            throw jiraIssueTypesError
        }

        return jiraIssueTypesByProjectKey[projectKey] ?? []
    }

    func resumeJiraIssueTypeFetch(
        for projectKey: String,
        with result: Result<[JiraIssueTypeOption], Error>
    ) {
        guard let index = jiraIssueTypeFetchContinuations.firstIndex(where: { $0.projectKey == projectKey }) else {
            return
        }

        let continuation = jiraIssueTypeFetchContinuations.remove(at: index).continuation
        switch result {
        case .success(let issueTypes):
            continuation.resume(returning: issueTypes)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func validateGitHubConfiguration(
        _ configuration: GitHubExportConfiguration
    ) async throws {
        gitHubValidationCallCount += 1

        if let gitHubValidationError {
            throw gitHubValidationError
        }
    }

    func validateJiraConfiguration(
        _ configuration: JiraExportConfiguration
    ) async throws {
        jiraValidationCallCount += 1

        if let jiraValidationError {
            throw jiraValidationError
        }
    }

    func prepareGitHubExportReview(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration,
        apiKey: String,
        model: String
    ) async throws -> IssueExportReview {
        gitHubReviewCallCount += 1

        if let gitHubError {
            throw gitHubError
        }

        return gitHubReview ?? IssueExportReview(
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
        jiraReviewCallCount += 1

        if let jiraError {
            throw jiraError
        }

        return jiraReview ?? IssueExportReview(
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
        gitHubCallCount += 1
        lastGitHubIssues = issues

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
        lastJiraIssues = issues

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

    func makeRecordedAudioURL(
        in directoryURL: URL,
        sourceFileURL: URL
    ) -> URL {
        let fileExtension = sourceFileURL.pathExtension.isEmpty ? "m4a" : sourceFileURL.pathExtension
        return directoryURL
            .appendingPathComponent("recording")
            .appendingPathExtension(fileExtension)
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

@MainActor
final class MockScreenCapturePermissionAccess: ScreenCapturePermissionAccessing {
    var permissionState: ScreenCapturePermissionState = .granted
    var requestedPermissionStates: [ScreenCapturePermissionState] = []
    private(set) var permissionRequestCallCount = 0

    func currentPermissionState() -> ScreenCapturePermissionState {
        permissionState
    }

    func requestPermissionIfNeeded() async -> ScreenCapturePermissionState {
        permissionRequestCallCount += 1

        if permissionState == .notDetermined, !requestedPermissionStates.isEmpty {
            permissionState = requestedPermissionStates.removeFirst()
        }

        return permissionState
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
            throw KeychainError.interactionRequired
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
    let screenCapturePermissionAccess: MockScreenCapturePermissionAccess
    let screenshotSelectionService: MockScreenshotSelectionService
    let appState: AppState

    init(
        apiKey: String = "test-api-key",
        debugMode: Bool = false,
        autoCopyTranscript: Bool = true,
        autoSaveTranscript: Bool = true,
        autoExtractIssues: Bool = false,
        screenshotCaptureService: MockScreenshotCaptureService = MockScreenshotCaptureService(),
        screenshotSelectionService: MockScreenshotSelectionService = MockScreenshotSelectionService(),
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

func requestBodyData(from request: URLRequest) throws -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "BugNarratorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request body was missing."])
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? NSError(
                domain: "BugNarratorTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Request body stream could not be read."]
            )
        }

        if readCount == 0 {
            break
        }

        data.append(buffer, count: readCount)
    }

    return data
}
