import Foundation

/// A redacted description of a legacy-secret deletion that failed. Returned
/// (never thrown) so the caller can log it without aborting the primary
/// operation — the canonical-service delete is what actually matters.
struct LegacyDeletionFailure: Equatable {
    let service: String
    let redactedDetail: String
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
