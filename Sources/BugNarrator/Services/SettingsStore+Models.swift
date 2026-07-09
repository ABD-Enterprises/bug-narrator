import Foundation

extension SettingsStore {
    private static let openAITranscriptionModelChoices = [
        AIModelChoice(
            id: "whisper-1",
            title: "Whisper",
            detail: "Stable default"
        ),
        AIModelChoice(
            id: "gpt-4o-mini-transcribe",
            title: "GPT-4o mini Transcribe",
            detail: "Lower cost, newer speech-to-text"
        ),
        AIModelChoice(
            id: "gpt-4o-transcribe",
            title: "GPT-4o Transcribe",
            detail: "Higher accuracy speech-to-text"
        ),
        AIModelChoice(
            id: "gpt-4o-transcribe-diarize",
            title: "GPT-4o Transcribe Diarize",
            detail: "Adds speaker labels"
        )
    ]
    static let parakeetTranscriptionModel = "parakeet-tdt-0.6b-v3"
    private static let parakeetTranscriptionModelChoices = [
        AIModelChoice(
            id: parakeetTranscriptionModel,
            title: "Parakeet TDT 0.6B v3",
            detail: "Local transcription server"
        )
    ]
    private static let openAIIssueExtractionModelChoices = [
        AIModelChoice(
            id: "gpt-4.1-mini",
            title: "GPT-4.1 mini",
            detail: "Recommended default"
        ),
        AIModelChoice(
            id: "gpt-4.1-nano",
            title: "GPT-4.1 nano",
            detail: "Fastest and lowest cost"
        ),
        AIModelChoice(
            id: "gpt-4.1",
            title: "GPT-4.1",
            detail: "Higher quality issue extraction"
        )
    ]

    var preferredModelValue: String {
        Self.normalizedTranscriptionModel(preferredModel, for: aiProvider)
    }

    var issueExtractionModelValue: String {
        Self.normalizedIssueExtractionModel(issueExtractionModel, for: aiProvider)
    }

    var transcriptionModelChoices: [AIModelChoice] {
        Self.transcriptionModelChoices(for: aiProvider)
    }

    var issueExtractionModelChoices: [AIModelChoice] {
        Self.issueExtractionModelChoices(for: aiProvider)
    }

    static func transcriptionModelChoices(for provider: AIProvider) -> [AIModelChoice] {
        switch provider {
        case .openAI:
            return openAITranscriptionModelChoices
        case .parakeetLocal:
            return parakeetTranscriptionModelChoices
        case .openAICompatible, .localCompatible:
            return []
        }
    }

    static func issueExtractionModelChoices(for provider: AIProvider) -> [AIModelChoice] {
        switch provider {
        case .openAI:
            return openAIIssueExtractionModelChoices
        case .openAICompatible, .localCompatible, .parakeetLocal:
            return []
        }
    }

    static func normalizedTranscriptionModel(_ rawValue: String, for provider: AIProvider) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAI:
            let allowedModels = Set(openAITranscriptionModelChoices.map(\.id))
            return allowedModels.contains(value) ? value : openAITranscriptionModel
        case .parakeetLocal:
            return parakeetTranscriptionModel
        case .openAICompatible, .localCompatible:
            return value.isEmpty ? openAITranscriptionModel : value
        }
    }

    static func normalizedIssueExtractionModel(_ rawValue: String, for provider: AIProvider) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch provider {
        case .openAI:
            let allowedModels = Set(openAIIssueExtractionModelChoices.map(\.id))
            return allowedModels.contains(value) ? value : openAIIssueExtractionModel
        case .openAICompatible, .localCompatible, .parakeetLocal:
            return value.isEmpty ? openAIIssueExtractionModel : value
        }
    }
}
