import Foundation

/// A redacted description of a legacy-secret deletion that failed. Returned
/// (never thrown) so the caller can log it without aborting the primary
/// operation — the canonical-service delete is what actually matters.
struct LegacyDeletionFailure: Equatable {
    let service: String
    let redactedDetail: String
}

/// Raw Keychain I/O for a `SecretSlot`, extracted from `SettingsStore`
/// (#429 credential slice 3b).
///
/// This seam knows only how to read/write/delete a slot's canonical and legacy
/// Keychain entries and how to redact a Keychain error. It holds **no**
/// persistence state, touches **no** `UserDefaults`, and knows nothing about
/// `APIKeyPersistenceState` or `AIProvider`. `SettingsStore` remains the
/// orchestrator that decides state transitions, session-only fallbacks,
/// provider tagging, migration, and all logging.
protocol KeychainSecretStoring {
    /// Write a slot's canonical Keychain entry.
    func saveCanonicalValue(_ value: String, for slot: SecretSlot) throws

    /// Read a slot's canonical Keychain entry (may be `nil` / empty).
    func readCanonicalValue(for slot: SecretSlot, allowInteraction: Bool) throws -> String?

    /// Read the first non-empty value across a slot's legacy service names, in
    /// order. Returns `nil` when no legacy entry holds a value.
    func readFirstLegacyValue(for slot: SecretSlot, allowInteraction: Bool) throws -> String?

    /// Delete a slot's canonical Keychain entry.
    func deleteCanonicalValue(for slot: SecretSlot) throws

    /// Best-effort delete of every legacy Keychain entry for a slot. Never
    /// throws; returns the per-service failures for the caller to log.
    func deleteLegacyValues(for slot: SecretSlot) -> [LegacyDeletionFailure]

    /// Render a Keychain error for diagnostics without any secret material
    /// (only the error type / OSStatus code).
    static func redactedErrorDetail(_ error: Error) -> String
}

struct KeychainSecretStore: KeychainSecretStoring {
    private let keychainService: KeychainServicing

    init(keychainService: KeychainServicing) {
        self.keychainService = keychainService
    }

    func saveCanonicalValue(_ value: String, for slot: SecretSlot) throws {
        try keychainService.setString(value, service: slot.service, account: slot.account)
    }

    func readCanonicalValue(for slot: SecretSlot, allowInteraction: Bool) throws -> String? {
        try keychainService.string(
            forService: slot.service,
            account: slot.account,
            allowInteraction: allowInteraction
        )
    }

    func readFirstLegacyValue(for slot: SecretSlot, allowInteraction: Bool) throws -> String? {
        for legacyService in slot.legacyServices {
            if let legacyValue = try keychainService.string(
                forService: legacyService,
                account: slot.account,
                allowInteraction: allowInteraction
            ),
               !legacyValue.isEmpty {
                return legacyValue
            }
        }
        return nil
    }

    func deleteCanonicalValue(for slot: SecretSlot) throws {
        try keychainService.deleteValue(service: slot.service, account: slot.account)
    }

    func deleteLegacyValues(for slot: SecretSlot) -> [LegacyDeletionFailure] {
        var failures: [LegacyDeletionFailure] = []
        for service in slot.legacyServices {
            do {
                try keychainService.deleteValue(service: service, account: slot.account)
            } catch {
                failures.append(
                    LegacyDeletionFailure(
                        service: service,
                        redactedDetail: Self.redactedErrorDetail(error)
                    )
                )
            }
        }
        return failures
    }

    static func redactedErrorDetail(_ error: Error) -> String {
        if case KeychainError.unhandledStatus(let status) = error {
            return "osstatus_\(status)"
        }
        return String(describing: type(of: error))
    }
}
