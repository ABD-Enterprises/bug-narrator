import Foundation

extension SettingsStore {

    var maskedAPIKey: String {
        mask(
            secret: trimmedAPIKey,
            persistenceState: apiKeyPersistenceState,
            emptyPlaceholder: "No key saved",
            lockedPlaceholder: "Saved key locked"
        )
    }

    var maskedSelectedAIProviderCredential: String {
        let persistenceState = selectedAIProviderCredentialPersistenceState
        return mask(
            secret: persistenceState == .empty ? "" : trimmedAPIKey,
            persistenceState: persistenceState,
            emptyPlaceholder: aiProvider == .parakeetLocal ? "No key required" : "No key saved",
            lockedPlaceholder: "Saved key locked"
        )
    }

    var maskedGitHubToken: String {
        mask(
            secret: trimmedGitHubToken,
            persistenceState: githubTokenPersistenceState,
            emptyPlaceholder: "No token saved",
            lockedPlaceholder: "Saved token locked"
        )
    }

    var maskedJiraAPIToken: String {
        mask(
            secret: trimmedJiraAPIToken,
            persistenceState: jiraTokenPersistenceState,
            emptyPlaceholder: "No token saved",
            lockedPlaceholder: "Saved token locked"
        )
    }

    private func mask(
        secret: String,
        persistenceState: APIKeyPersistenceState,
        emptyPlaceholder: String,
        lockedPlaceholder: String
    ) -> String {
        guard !secret.isEmpty else {
            switch persistenceState {
            case .keychain:
                return "Saved key"
            case .keychainLocked:
                return lockedPlaceholder
            default:
                return emptyPlaceholder
            }
        }

        let suffixCount = min(4, secret.count)
        let suffix = secret.suffix(suffixCount)
        return "••••••••\(suffix)"
    }

}
