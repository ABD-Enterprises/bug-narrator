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

    /// Rejects a remote `http://` base URL. Loopback, private-range and
    /// link-local hosts stay allowed — that is the whole Parakeet / LM Studio /
    /// Ollama story, and the shipped defaults are themselves `http://localhost`.
    /// A `.local` or single-label host does not: both resolve over mDNS, which
    /// any device on the local network can answer. Parakeet is exempt outright
    /// because `normalizedOpenAIBaseURL` ignores the typed value for that
    /// provider.
    var remotePlaintextEndpointIssue: String? {
        guard aiProvider != .parakeetLocal else {
            return nil
        }

        let url = SettingsStore.normalizedOpenAIBaseURL(from: openAIBaseURL, provider: aiProvider)
        guard url.scheme?.lowercased() == "http" else { return nil }
        // The host is read as it was written: Foundation takes the brackets
        // off whatever is in them, so `[localhost]` would read as the
        // reserved name and `[127.0.0.1]` as the loopback.
        let host = SettingsStore.hostAsWritten(url) ?? url.host ?? ""
        guard !SettingsStore.isLocalEndpointHost(host) else { return nil }

        return SettingsStore.plaintextTransportRefusal(
            host: host,
            subject: "This endpoint",
            secret: "API key and transcript text",
            localNoun: "endpoint"
        )
    }

    var aiProviderConfigurationIsReady: Bool {
        switch aiProvider {
        case .parakeetLocal:
            return aiProviderCompatibilityIssue == nil &&
                currentLocalProviderReachability() == .reachable
        default:
            return aiProviderCompatibilityIssue == nil && hasUsableAIProviderCredential
        }
    }

    var aiProviderCompatibilityIssue: String? {
        // Security first, ahead of every configuration check: a remote
        // plaintext endpoint is not a preference, it is a credential and audio
        // leak. Warning about it was not enough — nothing consumed the warning
        // as a gate, so one mistyped scheme shipped the API key and the
        // recording over the network in the clear (#953).
        if let plaintextIssue = remotePlaintextEndpointIssue {
            return plaintextIssue
        }

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
            guard currentLocalProviderReachability() == .reachable else {
                return localProviderUnreachableMessage
            }
            return nil
        }
    }
}
