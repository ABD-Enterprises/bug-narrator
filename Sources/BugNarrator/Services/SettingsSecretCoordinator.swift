import Foundation

struct LoadedSecret {
    let value: String
    let state: APIKeyPersistenceState
}

final class SettingsSecretCoordinator {
    private let defaults: UserDefaults
    private let secretStore: KeychainSecretStoring
    private let aiProviderCredentialProviderKey: String
    private let logger = DiagnosticsLogger(category: .settings)
    private var sessionOnlySecrets: [SecretSlot: String] = [:]
    private var committedSecrets: [SecretSlot: String] = [:]
    private var committedStates: [SecretSlot: APIKeyPersistenceState] = [:]

    init(
        defaults: UserDefaults,
        secretStore: KeychainSecretStoring,
        aiProviderCredentialProviderKey: String
    ) {
        self.defaults = defaults
        self.secretStore = secretStore
        self.aiProviderCredentialProviderKey = aiProviderCredentialProviderKey
    }

    func load(
        slot: SecretSlot,
        allowInteraction: Bool,
        includeLegacyServices: Bool,
        aiProvider: AIProvider
    ) -> LoadedSecret {
        do {
            if let value = try secretStore.readCanonicalValue(
                for: slot,
                allowInteraction: allowInteraction
            ),
               !value.isEmpty {
                return LoadedSecret(value: value, state: .keychain)
            }

            if includeLegacyServices,
               let value = try secretStore.readFirstLegacyValue(
                for: slot,
                allowInteraction: allowInteraction
               ) {
                _ = persist(value, for: slot, aiProvider: aiProvider)
                return LoadedSecret(value: value, state: .keychain)
            }
        } catch {
            if let value = sessionOnlySecrets[slot], !value.isEmpty {
                logger.warning(
                    "secret_fallback_to_memory",
                    "Keychain access failed, so BugNarrator fell back to an in-memory secure value.",
                    metadata: ["slot": slot.redactionSafeName]
                )
                return LoadedSecret(value: value, state: .sessionOnly)
            }

            if case KeychainError.interactionRequired = error {
                logger.debug(
                    "secret_locked",
                    "A secure value remains in Keychain, but BugNarrator skipped the unlock prompt until a user-initiated action needs it.",
                    metadata: [
                        "slot": slot.redactionSafeName,
                        "allow_interaction": allowInteraction ? "yes" : "no"
                    ]
                )
                return LoadedSecret(value: "", state: .keychainLocked)
            }

            logger.debug(
                "secret_unavailable",
                "A secure value was unavailable during reload.",
                metadata: [
                    "slot": slot.redactionSafeName,
                    "allow_interaction": allowInteraction ? "yes" : "no"
                ]
            )
            return LoadedSecret(value: "", state: .empty)
        }

        if let value = sessionOnlySecrets[slot], !value.isEmpty {
            return LoadedSecret(value: value, state: .sessionOnly)
        }
        return LoadedSecret(value: "", state: .empty)
    }

    @discardableResult
    func persist(_ value: String, for slot: SecretSlot, aiProvider: AIProvider) -> APIKeyPersistenceState {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            sessionOnlySecrets.removeValue(forKey: slot)
            do {
                try secretStore.deleteCanonicalValue(for: slot)
            } catch {
                logger.warning(
                    "secret_clear_failed",
                    "A secure value could not be removed from Keychain.",
                    metadata: [
                        "slot": slot.redactionSafeName,
                        "error": KeychainSecretStore.redactedErrorDetail(error)
                    ]
                )
                committedStates[slot] = .keychain
                return .keychain
            }
            deleteLegacySecrets(for: slot)
            logger.info(
                "secret_cleared",
                "A secure value was cleared from persistent storage.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.removeObject(forKey: aiProviderCredentialProviderKey)
            }
            committedSecrets[slot] = ""
            committedStates[slot] = .empty
            return .empty
        }

        do {
            try secretStore.saveCanonicalValue(trimmedValue, for: slot)
            deleteLegacySecrets(for: slot)
            sessionOnlySecrets.removeValue(forKey: slot)
            logger.info(
                "secret_persisted",
                "A secure value was saved to Keychain.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.set(aiProvider.rawValue, forKey: aiProviderCredentialProviderKey)
            }
            committedSecrets[slot] = slot == .openAI ? "" : trimmedValue
            committedStates[slot] = .keychain
            return .keychain
        } catch {
            sessionOnlySecrets[slot] = trimmedValue
            logger.warning(
                "secret_persisted_in_memory",
                "Keychain storage was unavailable, so a secure value is only kept in memory for this run.",
                metadata: ["slot": slot.redactionSafeName]
            )
            if slot == .openAI {
                defaults.set(aiProvider.rawValue, forKey: aiProviderCredentialProviderKey)
            }
            committedSecrets[slot] = trimmedValue
            committedStates[slot] = .sessionOnly
            return .sessionOnly
        }
    }

    func recordLoaded(_ secret: LoadedSecret, for slot: SecretSlot) {
        committedSecrets[slot] = slot == .openAI && secret.state == .keychain ? "" : secret.value
        committedStates[slot] = secret.state
    }

    func stateAfterEditing(_ value: String, for slot: SecretSlot) -> APIKeyPersistenceState {
        let currentValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let committedValue = (committedSecrets[slot] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let committedState = committedStates[slot] ?? .empty
        if currentValue == committedValue {
            return committedState
        }
        if currentValue.isEmpty && committedState == .empty {
            return .empty
        }
        return .pendingSave
    }

    private func deleteLegacySecrets(for slot: SecretSlot) {
        for failure in secretStore.deleteLegacyValues(for: slot) {
            logger.warning(
                "secret_legacy_clear_failed",
                "A legacy secure value could not be removed from Keychain.",
                metadata: [
                    "slot": slot.redactionSafeName,
                    "error": failure.redactedDetail
                ]
            )
        }
    }
}
