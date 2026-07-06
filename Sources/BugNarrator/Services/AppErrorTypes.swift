import Foundation

enum AppErrorOperation: String {
    case generic
    case recordingStart = "recording_start"
    case recordingStop = "recording_stop"
    case transcription
    case retryTranscription = "retry_transcription"
    case postTranscription = "post_transcription"
    case screenshotCapture = "screenshot_capture"
    case diagnosticsExport = "diagnostics_export"
    case privacyExport = "privacy_export"
    case export
    case sessionLibrary = "session_library"
    case issueExtraction = "issue_extraction"
}

struct AppErrorNormalization: Equatable {
    let appError: AppError
    let operation: AppErrorOperation
    let underlyingErrorDescription: String?
}

