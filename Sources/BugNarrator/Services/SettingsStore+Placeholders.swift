import Foundation

extension SettingsStore {
    var supportsIssueExtraction: Bool {
        aiProvider != .parakeetLocal
    }

    var transcriptionModelPlaceholder: String {
        switch aiProvider {
        case .openAI:
            return Self.openAITranscriptionModel
        case .openAICompatible:
            return "Provider transcription model"
        case .localCompatible:
            return "Local transcription model"
        case .parakeetLocal:
            return Self.parakeetTranscriptionModel
        }
    }

    var issueExtractionModelPlaceholder: String {
        switch aiProvider {
        case .openAI:
            return Self.openAIIssueExtractionModel
        case .openAICompatible:
            return "Provider chat model"
        case .localCompatible:
            return "Local chat model"
        case .parakeetLocal:
            return "Not available"
        }
    }
}
