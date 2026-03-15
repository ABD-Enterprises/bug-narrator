import Foundation

enum MicrophonePermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

@MainActor
protocol AudioRecording: AnyObject {
    var currentDuration: TimeInterval { get }
    func microphonePermissionState() -> MicrophonePermissionState
    func startRecording() async throws
    func stopRecording() async throws -> RecordedAudio
    func cancelRecording(preserveFile: Bool) async
}

protocol TranscriptionServing: Sendable {
    func transcribe(fileURL: URL, apiKey: String, request: TranscriptionRequest) async throws -> TranscriptionResult
    func validateAPIKey(_ apiKey: String) async throws
}

protocol HotkeyManaging: AnyObject {
    var onHotKeyPressed: ((HotkeyAction) -> Void)? { get set }
    func register(shortcut: HotkeyShortcut, for action: HotkeyAction)
    func unregisterAll()
}

protocol ScreenshotCapturing {
    @MainActor
    func captureScreenshot(to url: URL) async throws
}

protocol IssueExtracting: Sendable {
    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String
    ) async throws -> IssueExtractionResult
}

protocol IssueExporting: Sendable {
    func exportToGitHub(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult]

    func exportToJira(
        issues: [ExtractedIssue],
        session: TranscriptSession,
        configuration: JiraExportConfiguration
    ) async throws -> [ExportResult]
}

protocol SessionArtifactsManaging {
    func createArtifactsDirectory(for sessionID: UUID) throws -> URL
    func makeScreenshotURL(
        in directoryURL: URL,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval
    ) -> URL
    func removeArtifactsDirectory(at directoryURL: URL)
}

protocol ClipboardWriting {
    func copy(_ string: String)
}

protocol KeychainServicing {
    func string(forService service: String, account: String, allowInteraction: Bool) throws -> String?
    func setString(_ value: String, service: String, account: String) throws
    func deleteValue(service: String, account: String) throws
}

extension KeychainServicing {
    func string(forService service: String, account: String) throws -> String? {
        try string(forService: service, account: account, allowInteraction: true)
    }
}

protocol URLOpening {
    @discardableResult
    func open(_ url: URL) -> Bool
}
