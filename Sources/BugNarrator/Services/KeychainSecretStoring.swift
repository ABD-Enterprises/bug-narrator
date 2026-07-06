import Foundation

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

