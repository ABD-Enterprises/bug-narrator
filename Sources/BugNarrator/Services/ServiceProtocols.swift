import Foundation

enum MicrophonePermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
}

enum MicrophonePermissionStatus: String, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable
    case captureSetupFailed
    case unknownError
}

struct MicrophoneRecoveryGuidance: Equatable {
    let headline: String
    let message: String
    let localTestingNote: String?
}

enum RecordingStartPreflightResult: Equatable {
    case success
    case blocked(AppError)
    case needsUserAction(AppError)
    case failure(AppError)

    var error: AppError? {
        switch self {
        case .success:
            return nil
        case .blocked(let error), .needsUserAction(let error), .failure(let error):
            return error
        }
    }
}

enum ScreenCapturePermissionState: Equatable {
    case granted
    case notDetermined
    case denied
    case unavailable
}

enum ScreenCapturePermissionStatus: String, Equatable {
    case notDetermined
    case granted
    case denied
    case unavailable
    case captureSetupFailed
    case unknownError
}

struct ScreenCaptureRecoveryGuidance: Equatable {
    let headline: String
    let message: String
}

enum ScreenshotCapturePreflightResult: Equatable {
    case success
    case blocked(AppError)
    case needsUserAction(AppError)
    case failure(AppError)

    var error: AppError? {
        switch self {
        case .success:
            return nil
        case .blocked(let error), .needsUserAction(let error), .failure(let error):
            return error
        }
    }
}

enum ScreenshotSelectionResult: Equatable {
    case selected(CGRect)
    case cancelled
}

@MainActor
protocol AudioRecording: AnyObject {
    var currentDuration: TimeInterval { get }
    func microphonePermissionState() -> MicrophonePermissionState
    func validateRecordingPrerequisites() async -> AppError?
    func validateRecordingActivation() async -> AppError?
    func startRecording() async throws
    func stopRecording() async throws -> RecordedAudio
    func cancelRecording(preserveFile: Bool) async
}

@MainActor
protocol MicrophonePermissionAccessing {
    func currentPermissionState() -> MicrophonePermissionState
    func requestPermissionIfNeeded() async -> MicrophonePermissionState
}

@MainActor
protocol ScreenCapturePermissionAccessing {
    func currentPermissionState() -> ScreenCapturePermissionState
    func requestPermissionIfNeeded() async -> ScreenCapturePermissionState
}

@MainActor
protocol MicrophonePermissionServicing {
    func currentStatus() -> MicrophonePermissionStatus
    func recoveryGuidance(
        for status: MicrophonePermissionStatus,
        runtimeEnvironment: AppRuntimeEnvironment
    ) -> MicrophoneRecoveryGuidance
    func preflightForRecordingStart(audioRecorder: any AudioRecording) async -> RecordingStartPreflightResult
}

@MainActor
protocol ScreenCapturePermissionServicing {
    func currentStatus() -> ScreenCapturePermissionStatus
    func recoveryGuidance(
        for status: ScreenCapturePermissionStatus,
        runtimeEnvironment: AppRuntimeEnvironment
    ) -> ScreenCaptureRecoveryGuidance
    func preflightForScreenshotCapture(
        screenshotCaptureService: any ScreenshotCapturing,
        hasActiveRecordingSession: Bool
    ) async -> ScreenshotCapturePreflightResult
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
    func validateCaptureAvailability() async -> AppError?
    @MainActor
    func captureScreenshot(in rect: CGRect, to url: URL) async throws
}

@MainActor
protocol ScreenshotSelecting {
    func selectRegion() async throws -> ScreenshotSelectionResult
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
