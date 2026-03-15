import Foundation

enum AppError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidAPIKey
    case revokedAPIKey
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case microphoneUnavailable(String)
    case screenRecordingPermissionDenied
    case noActiveSession(String)
    case recordingFailure(String)
    case transcriptionFailure(String)
    case openAIRequestRejected(String)
    case screenshotCaptureFailure(String)
    case issueExtractionFailure(String)
    case emptyTranscript
    case networkTimeout
    case networkFailure
    case exportConfigurationMissing(String)
    case exportFailure(String)
    case storageFailure(String)
    case diagnosticsFailure(String)

    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "BugNarrator requires your own OpenAI API key for transcription and issue extraction. Add it in Settings before stopping the session."
        case .invalidAPIKey:
            return "The OpenAI API key was rejected. Open Settings, replace it, and try again."
        case .revokedAPIKey:
            return "The OpenAI API key is no longer valid. Open Settings, remove it, and add a new key."
        case .microphonePermissionDenied:
            return "Microphone permission was denied. Open System Settings > Privacy & Security > Microphone, enable BugNarrator, then try again."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted on this Mac. Check System Settings > Privacy & Security > Microphone and any device-management or parental-control restrictions, then try again."
        case .microphoneUnavailable(let message):
            return "BugNarrator could not start audio capture. \(message)"
        case .screenRecordingPermissionDenied:
            return "Screenshot capture requires Screen Recording permission. Recording can continue without screenshots. Open System Settings > Privacy & Security > Screen & System Audio Recording, enable BugNarrator, then try again."
        case .noActiveSession(let message):
            return message
        case .recordingFailure(let message):
            return "Recording failed: \(message)"
        case .transcriptionFailure(let message):
            return "Transcription failed: \(message)"
        case .openAIRequestRejected(let message):
            return "OpenAI rejected the request: \(message)"
        case .screenshotCaptureFailure(let message):
            return "Screenshot capture failed: \(message)"
        case .issueExtractionFailure(let message):
            return "Issue extraction failed: \(message)"
        case .emptyTranscript:
            return "The transcription finished but returned empty text."
        case .networkTimeout:
            return "The request to OpenAI timed out. Check your connection and try again."
        case .networkFailure:
            return "BugNarrator could not reach OpenAI. Check your internet connection and try again."
        case .exportConfigurationMissing(let message):
            return "Export setup is incomplete: \(message)"
        case .exportFailure(let message):
            return "Export failed: \(message)"
        case .storageFailure(let message):
            return "Could not save local session history: \(message)"
        case .diagnosticsFailure(let message):
            return "BugNarrator could not prepare diagnostics: \(message)"
        }
    }

    var statusTitle: String {
        switch self {
        case .missingAPIKey:
            return "OpenAI Key Needed"
        case .invalidAPIKey, .revokedAPIKey:
            return "OpenAI Key Rejected"
        case .microphonePermissionDenied:
            return "Microphone Access Needed"
        case .microphonePermissionRestricted:
            return "Microphone Access Restricted"
        case .microphoneUnavailable:
            return "Microphone Unavailable"
        case .screenRecordingPermissionDenied:
            return "Screen Recording Access Needed"
        case .recordingFailure:
            return "Recording Failed"
        case .transcriptionFailure, .openAIRequestRejected, .emptyTranscript:
            return "Transcription Failed"
        case .screenshotCaptureFailure:
            return "Screenshot Failed"
        case .issueExtractionFailure:
            return "Issue Extraction Failed"
        case .networkTimeout, .networkFailure:
            return "Network Issue"
        case .exportConfigurationMissing:
            return "Export Setup Needed"
        case .exportFailure:
            return "Export Failed"
        case .storageFailure:
            return "Local Save Failed"
        case .diagnosticsFailure:
            return "Diagnostics Failed"
        case .noActiveSession:
            return "Action Needed"
        }
    }

    var recoveryHeadline: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is blocked."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted."
        case .microphoneUnavailable:
            return "Audio capture is unavailable."
        case .screenRecordingPermissionDenied:
            return "Screen recording access is blocked."
        case .missingAPIKey:
            return "Add your OpenAI API key before continuing."
        case .invalidAPIKey, .revokedAPIKey:
            return "Replace your OpenAI API key before continuing."
        case .networkTimeout, .networkFailure:
            return "BugNarrator could not reach OpenAI."
        case .exportConfigurationMissing:
            return "Finish export setup before continuing."
        case .storageFailure:
            return "BugNarrator could not update local session history."
        default:
            return nil
        }
    }

    var errorDescription: String? {
        userMessage
    }

    var suggestsOpenAISettings: Bool {
        switch self {
        case .missingAPIKey, .invalidAPIKey, .revokedAPIKey:
            return true
        default:
            return false
        }
    }

    var suggestsMicrophoneSettings: Bool {
        switch self {
        case .microphonePermissionDenied, .microphonePermissionRestricted:
            return true
        default:
            return false
        }
    }
}
