import Foundation

extension SettingsStore {
    var normalizedLanguageHint: String? {
        normalizeOptional(languageHint)
    }

    var normalizedPrompt: String? {
        normalizeOptional(transcriptionPrompt)
    }

    var transcriptionRequest: TranscriptionRequest {
        TranscriptionRequest(
            model: preferredModelValue,
            languageHint: normalizedLanguageHint,
            prompt: normalizedPrompt,
            apiBaseURL: openAIBaseURLValue
        )
    }

    private func normalizeOptional(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
