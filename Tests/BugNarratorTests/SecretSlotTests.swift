import XCTest
@testable import BugNarrator

/// Freezes the Keychain-addressing contract for every `SecretSlot`. These
/// strings are how existing installs' secrets are found; changing any of them
/// without a migration would orphan a stored secret (Keychain data loss), so
/// they are asserted as exact literals (#429 credential slice 3a).
final class SecretSlotTests: XCTestCase {
    func testEverySlotAddressesTheExactKeychainLiterals() {
        // slot -> (service, account, legacyServices, redactionSafeName)
        let expected: [SecretSlot: (service: String, account: String, legacyServices: [String], redactionSafeName: String)] = [
            .openAI: ("BugNarrator.OpenAI", "openai-api-key", ["SessionMic.OpenAI"], "openai"),
            .github: ("BugNarrator.GitHub", "github-token", ["SessionMic.GitHub"], "github"),
            .jiraEmail: ("BugNarrator.Jira", "jira-email", ["SessionMic.Jira"], "jira-email"),
            .jira: ("BugNarrator.Jira", "jira-api-token", ["SessionMic.Jira"], "jira")
        ]

        // Every case is covered by the matrix (guards against a new slot slipping
        // in without a frozen contract).
        XCTAssertEqual(Set(SecretSlot.allCases), Set(expected.keys))

        for slot in SecretSlot.allCases {
            guard let fields = expected[slot] else {
                XCTFail("missing expected literals for slot \(slot)")
                continue
            }
            XCTAssertEqual(slot.service, fields.service)
            XCTAssertEqual(slot.account, fields.account)
            XCTAssertEqual(slot.legacyServices, fields.legacyServices)
            XCTAssertEqual(slot.redactionSafeName, fields.redactionSafeName)
        }
    }

    func testCaseIterableOrderIsStable() {
        // Order is relied on by callers that iterate export slots; freeze it.
        XCTAssertEqual(SecretSlot.allCases, [.openAI, .github, .jiraEmail, .jira])
    }

    func testEverySlotHasAUniqueServiceAccountAddress() {
        // jiraEmail/jira deliberately share a service but differ by account, so
        // the FULL (service, account) key must still be unique across every
        // slot — an accidental collision on both would make two credentials
        // fight over one Keychain entry (silent data loss / overwrite).
        let addresses = SecretSlot.allCases.map { "\($0.service)|\($0.account)" }
        XCTAssertEqual(Set(addresses).count, SecretSlot.allCases.count)
    }

    func testJiraEmailAndTokenShareServiceButDifferByAccount() {
        // Both Jira secrets intentionally live under one Keychain service and are
        // disambiguated by account — regressing this would collide or orphan them.
        XCTAssertEqual(SecretSlot.jiraEmail.service, SecretSlot.jira.service)
        XCTAssertEqual(SecretSlot.jiraEmail.service, "BugNarrator.Jira")
        XCTAssertNotEqual(SecretSlot.jiraEmail.account, SecretSlot.jira.account)
        XCTAssertEqual(SecretSlot.jiraEmail.account, "jira-email")
        XCTAssertEqual(SecretSlot.jira.account, "jira-api-token")
    }
}
