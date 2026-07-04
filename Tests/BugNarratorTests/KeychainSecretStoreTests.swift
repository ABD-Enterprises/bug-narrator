import XCTest
@testable import BugNarrator

/// Proves the raw-Keychain seam addresses each `SecretSlot` exactly as
/// `SettingsStore` did inline (#429 credential slice 3b). Addressing is the
/// no-data-loss contract: a wrong service/account would orphan an existing
/// secret.
final class KeychainSecretStoreTests: XCTestCase {
    private func makeStore() -> (KeychainSecretStore, MockKeychainService) {
        let keychain = MockKeychainService()
        return (KeychainSecretStore(keychainService: keychain), keychain)
    }

    private func key(_ service: String, _ account: String) -> String {
        "\(service)::\(account)"
    }

    func testSaveCanonicalWritesExactServiceAndAccountForEverySlot() throws {
        for slot in SecretSlot.allCases {
            let (store, keychain) = makeStore()
            try store.saveCanonicalValue("secret-\(slot.redactionSafeName)", for: slot)
            XCTAssertEqual(
                keychain.values[key(slot.service, slot.account)],
                "secret-\(slot.redactionSafeName)"
            )
            // Nothing written anywhere else.
            XCTAssertEqual(keychain.values.count, 1)
        }
    }

    func testReadCanonicalReadsOnlyCanonicalAddress() throws {
        for slot in SecretSlot.allCases {
            let (store, keychain) = makeStore()
            keychain.values[key(slot.service, slot.account)] = "canon"
            // Seed a legacy value too — canonical read must ignore it.
            for legacy in slot.legacyServices {
                keychain.values[key(legacy, slot.account)] = "legacy"
            }

            XCTAssertEqual(try store.readCanonicalValue(for: slot, allowInteraction: true), "canon")
            XCTAssertEqual(keychain.readRequests.count, 1)
            XCTAssertEqual(keychain.readRequests.first?.service, slot.service)
            XCTAssertEqual(keychain.readRequests.first?.account, slot.account)
            XCTAssertEqual(keychain.readRequests.first?.allowInteraction, true)
        }
    }

    func testReadFirstLegacyReadsLegacyServicesWithCanonicalAccount() throws {
        for slot in SecretSlot.allCases {
            let (store, keychain) = makeStore()
            // No canonical value; a legacy value exists under the canonical account.
            guard let firstLegacy = slot.legacyServices.first else {
                XCTFail("slot \(slot) has no legacy service")
                continue
            }
            keychain.values[key(firstLegacy, slot.account)] = "legacy-value"

            XCTAssertEqual(
                try store.readFirstLegacyValue(for: slot, allowInteraction: false),
                "legacy-value"
            )
            // Reads used the legacy service + the slot's canonical account.
            XCTAssertTrue(keychain.readRequests.contains { $0.service == firstLegacy && $0.account == slot.account })
        }
    }

    func testReadFirstLegacyReturnsNilWhenNoLegacyValuePresent() throws {
        let (store, _) = makeStore()
        XCTAssertNil(try store.readFirstLegacyValue(for: .github, allowInteraction: true))
    }

    func testDeleteCanonicalDeletesOnlyCanonicalAddress() throws {
        let slot = SecretSlot.jira
        let (store, keychain) = makeStore()
        keychain.values[key(slot.service, slot.account)] = "canon"
        keychain.values[key(slot.legacyServices[0], slot.account)] = "legacy"

        try store.deleteCanonicalValue(for: slot)

        XCTAssertNil(keychain.values[key(slot.service, slot.account)])
        // Legacy entry untouched by a canonical delete.
        XCTAssertEqual(keychain.values[key(slot.legacyServices[0], slot.account)], "legacy")
    }

    func testDeleteLegacyValuesDeletesEveryLegacyServiceButNotCanonical() throws {
        for slot in SecretSlot.allCases {
            let (store, keychain) = makeStore()
            keychain.values[key(slot.service, slot.account)] = "canon"
            for legacy in slot.legacyServices {
                keychain.values[key(legacy, slot.account)] = "legacy"
            }

            let failures = store.deleteLegacyValues(for: slot)

            XCTAssertTrue(failures.isEmpty)
            for legacy in slot.legacyServices {
                XCTAssertNil(keychain.values[key(legacy, slot.account)], "legacy \(legacy) should be gone")
            }
            // Canonical survives.
            XCTAssertEqual(keychain.values[key(slot.service, slot.account)], "canon")
        }
    }

    func testDeleteLegacyValuesReturnsRedactedFailuresInsteadOfThrowing() {
        let slot = SecretSlot.openAI
        let (store, keychain) = makeStore()
        keychain.deleteError = KeychainError.unhandledStatus(-25300)

        let failures = store.deleteLegacyValues(for: slot)

        XCTAssertEqual(failures.count, slot.legacyServices.count)
        XCTAssertEqual(failures.first?.service, slot.legacyServices.first)
        XCTAssertEqual(failures.first?.redactedDetail, "osstatus_-25300")
    }

    func testRedactedErrorDetailMapsOSStatusAndFallsBackToType() {
        XCTAssertEqual(
            KeychainSecretStore.redactedErrorDetail(KeychainError.unhandledStatus(-42)),
            "osstatus_-42"
        )
        struct SomeOtherError: Error {}
        XCTAssertEqual(
            KeychainSecretStore.redactedErrorDetail(SomeOtherError()),
            "SomeOtherError"
        )
    }
}
