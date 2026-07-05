import Foundation

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case openAI
    case openAICompatible
    case localCompatible
    case parakeetLocal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openAICompatible:
            return "OpenAI-Compatible"
        case .localCompatible:
            return "Local-Compatible"
        case .parakeetLocal:
            return "Local (Parakeet)"
        }
    }

    var setupDescription: String {
        switch self {
        case .openAI:
            return "Use OpenAI-hosted transcription and issue extraction with your own API key."
        case .openAICompatible:
            return "Use an enterprise proxy or hosted provider that exposes OpenAI-compatible endpoints."
        case .localCompatible:
            return "Use a local or self-hosted endpoint such as LM Studio or Ollama when it exposes OpenAI-compatible APIs."
        case .parakeetLocal:
            return "Transcribe locally on this Mac using Parakeet. No API key, no upload, fully offline after setup."
        }
    }

    var baseURLPlaceholder: String {
        switch self {
        case .openAI:
            return "https://api.openai.com"
        case .openAICompatible:
            return "https://gateway.example.com/openai"
        case .localCompatible:
            return "http://localhost:1234/v1"
        case .parakeetLocal:
            return "http://localhost:8422"
        }
    }

    var baseURLHint: String {
        switch self {
        case .openAI:
            return "Leave blank to use the default OpenAI API endpoint."
        case .openAICompatible:
            return "Enter the enterprise or hosted OpenAI-compatible base URL."
        case .localCompatible:
            return "Enter the local-compatible base URL. BugNarrator will not assume api.openai.com for this provider."
        case .parakeetLocal:
            return "BugNarrator connects to the local Parakeet transcription server on this port."
        }
    }

    var credentialFieldTitle: String {
        switch self {
        case .openAI:
            return "OpenAI API Key"
        case .openAICompatible:
            return "Provider API Key"
        case .localCompatible:
            return "Provider API Key (Optional)"
        case .parakeetLocal:
            return ""
        }
    }

    var validationActionTitle: String {
        switch self {
        case .openAI:
            return "Validate Key"
        case .openAICompatible, .localCompatible:
            return "Validate Connection"
        case .parakeetLocal:
            return "Check Server"
        }
    }

    var successMessage: String {
        switch self {
        case .openAI:
            return "OpenAI accepted this key."
        case .openAICompatible:
            return "The OpenAI-compatible provider accepted this configuration."
        case .localCompatible:
            return "The local-compatible provider accepted this configuration."
        case .parakeetLocal:
            return "The local Parakeet transcription server is running."
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .openAI, .openAICompatible:
            return true
        case .localCompatible, .parakeetLocal:
            return false
        }
    }

    var statusTitle: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .openAICompatible:
            return "Compatible Provider"
        case .localCompatible:
            return "Local Provider"
        case .parakeetLocal:
            return "Local Parakeet"
        }
    }
}
