import Foundation

extension SettingsStore {

    var apiKeyStorageDescription: String {
        if aiProvider.requiresAPIKey {
            return storageDescription(
                for: apiKeyPersistenceState,
                empty: "BugNarrator never ships with an API key. Paste your own \(aiProvider.displayName) credential to enable transcription."
            )
        }

        switch apiKeyPersistenceState {
        case .empty:
            return "Optional for local-compatible providers. Leave it blank if your endpoint does not require authentication."
        default:
            return storageDescription(
                for: apiKeyPersistenceState,
                empty: "Optional for local-compatible providers."
            )
        }
    }

    var selectedAIProviderCredentialStorageDescription: String {
        let persistenceState = selectedAIProviderCredentialPersistenceState

        if aiProvider == .parakeetLocal {
            return "Local Parakeet does not use an API key. Check the local server connection before transcribing."
        }

        if aiProvider.requiresAPIKey {
            return storageDescription(
                for: persistenceState,
                empty: "BugNarrator never ships with an API key. Paste your own \(aiProvider.displayName) credential to enable transcription."
            )
        }

        switch persistenceState {
        case .empty:
            return "Optional for local-compatible providers. Leave it blank if your endpoint does not require authentication."
        default:
            return storageDescription(
                for: persistenceState,
                empty: "Optional for local-compatible providers."
            )
        }
    }

    var githubTokenStorageDescription: String {
        storageDescription(
            for: githubTokenPersistenceState,
            empty: "Add a GitHub personal access token if you want to try the experimental GitHub Issues export."
        )
    }

    var jiraTokenStorageDescription: String {
        storageDescription(
            for: jiraTokenPersistenceState,
            empty: "Add Jira Cloud credentials if you want to try the experimental Jira export."
        )
    }

    private func storageDescription(for state: APIKeyPersistenceState, empty: String) -> String {
        switch state {
        case .empty:
            return empty
        case .keychain:
            return "Stored securely in your macOS Keychain."
        case .keychainLocked:
            return "Stored in your macOS Keychain. BugNarrator will only prompt to unlock it when you validate the key or run an action that needs it."
        case .sessionOnly:
            return "Keychain storage was unavailable, so this value is only kept in memory until you quit BugNarrator."
        case .pendingSave:
            return "Not saved yet. BugNarrator will only prompt to use Keychain when you validate the key or run an action that needs it."
        }
    }

}
