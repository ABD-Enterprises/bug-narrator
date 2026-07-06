import Foundation

enum PendingTranscriptionFailureReason: String, Codable, Equatable {
    case missingAPIKey
    case providerSetup
    case invalidAPIKey
    case revokedAPIKey
    case networkTimeout
    case networkFailure
    case rateLimited
    case providerRejected
    case transcriptionFailure
    case emptyTranscript
    case crashRecovery

    init?(appError: AppError) {
        switch appError {
        case .missingAPIKey:
            self = .missingAPIKey
        case .invalidAPIKey:
            self = .invalidAPIKey
        case .revokedAPIKey:
            self = .revokedAPIKey
        case .networkTimeout:
            self = .networkTimeout
        case .networkFailure:
            self = .networkFailure
        case .rateLimited:
            self = .rateLimited
        case .openAIRequestRejected:
            self = .providerRejected
        case .emptyTranscript:
            self = .emptyTranscript
        default:
            return nil
        }
    }

    func retryMessage(for provider: AIProvider) -> String {
        switch self {
        case .missingAPIKey:
            if provider.requiresAPIKey {
                return "Recording saved locally. Add your \(provider.displayName) API key in Settings, then retry transcription from this session."
            }
            return "Recording saved locally. Open Settings, confirm the \(provider.displayName) server setup, then retry transcription from this session."
        case .providerSetup:
            return "Recording saved locally. Finish the \(provider.displayName) setup in Settings, then retry transcription from this session."
        case .invalidAPIKey:
            if provider.requiresAPIKey {
                return "Recording saved locally. Replace the rejected \(provider.displayName) API key in Settings, then retry transcription from this session."
            }
            return "Recording saved locally. Open Settings, repair the \(provider.displayName) connection, then retry transcription from this session."
        case .revokedAPIKey:
            if provider.requiresAPIKey {
                return "Recording saved locally. Add a new \(provider.displayName) API key in Settings, then retry transcription from this session."
            }
            return "Recording saved locally. Open Settings, refresh the \(provider.displayName) configuration, then retry transcription from this session."
        case .networkTimeout:
            if provider == .parakeetLocal {
                return "Recording saved locally. The local transcription server did not respond. Start it, then retry transcription from this session."
            }
            return "Recording saved locally. The \(provider.displayName) request timed out, so retry transcription from this session when the connection is stable."
        case .networkFailure:
            if provider == .parakeetLocal {
                return "Recording saved locally. The local transcription server is not running. Start it, then retry transcription from this session."
            }
            return "Recording saved locally. BugNarrator could not reach \(provider.displayName), so retry transcription from this session when the connection is available."
        case .rateLimited:
            return "Recording saved locally. \(provider.displayName) rate limited the request, so wait a moment and retry transcription from this session."
        case .providerRejected:
            return "Recording saved locally. \(provider.displayName) rejected the transcription request, so review settings or retry from this session."
        case .transcriptionFailure:
            return "Recording saved locally. Transcription failed, so retry transcription from this session."
        case .emptyTranscript:
            return "Recording saved locally. Transcription returned empty text, so retry transcription from this session."
        case .crashRecovery:
            return "This older unexpected-quit recovery item is no longer supported. Delete it and start a new recording."
        }
    }

    func recoveryMessage(for provider: AIProvider) -> String {
        retryMessage(for: provider)
    }

    var recoveryMessage: String {
        retryMessage(for: .openAI)
    }

    var appError: AppError {
        switch self {
        case .missingAPIKey:
            return .missingAPIKey
        case .providerSetup:
            return .transcriptionFailure("The preserved recording is waiting for AI provider setup.")
        case .invalidAPIKey:
            return .invalidAPIKey
        case .revokedAPIKey:
            return .revokedAPIKey
        case .networkTimeout:
            return .networkTimeout
        case .networkFailure:
            return .networkFailure
        case .rateLimited:
            return .rateLimited(retryAfter: nil)
        case .providerRejected:
            return .openAIRequestRejected("The preserved recording is waiting for transcription retry.")
        case .transcriptionFailure:
            return .transcriptionFailure("The preserved recording is waiting for transcription retry.")
        case .emptyTranscript:
            return .emptyTranscript
        case .crashRecovery:
            return .transcriptionFailure("Unexpected-quit recording recovery is no longer supported.")
        }
    }
}
