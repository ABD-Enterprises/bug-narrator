import Foundation

extension SettingsStore {
    var hasAPIKey: Bool {
        credentialIsAvailableForUserAction(
            value: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState
        )
    }

    var hasUsableAIProviderCredential: Bool {
        switch aiProvider {
        case .openAI:
            return aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: true)
        case .openAICompatible:
            return aiProviderCredentialIsAvailableForCurrentProvider(allowsLegacyOpenAICredential: false)
        case .localCompatible, .parakeetLocal:
            return true
        }
    }

    var aiProviderConfigurationIsReady: Bool {
        aiProviderCompatibilityIssue == nil && hasUsableAIProviderCredential
    }

    var aiProviderCompatibilityIssue: String? {
        switch aiProvider {
        case .openAI:
            return nil
        case .openAICompatible:
            let trimmedBaseURL = openAIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBaseURL.isEmpty {
                return "Choose a non-default API base URL for the OpenAI-Compatible provider."
            }
            return nil
        case .localCompatible:
            if preferredModelValue == "whisper-1" {
                return "Choose a local transcription model instead of whisper-1 for the Local-Compatible provider."
            }
            if issueExtractionModelValue == "gpt-4.1-mini" {
                return "Choose a local issue extraction model instead of gpt-4.1-mini for the Local-Compatible provider."
            }
            return nil
        case .parakeetLocal:
            if autoExtractIssues {
                return "Turn off automatic issue extraction or choose a provider with a chat completion model."
            }
            return nil
        }
    }
}
