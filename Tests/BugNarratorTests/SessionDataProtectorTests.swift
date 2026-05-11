import Foundation
import XCTest
@testable import BugNarrator

final class SessionDataProtectorTests: XCTestCase {
    func testKeychainProtectorEncryptsAndDecryptsPayloads() throws {
        let keychain = MockKeychainService()
        let protector = KeychainSessionDataProtector(keychainService: keychain)
        let plaintext = Data("sensitive transcript".utf8)

        let protectedData = try protector.protect(plaintext)
        let unprotectedData = try protector.unprotect(protectedData)

        XCTAssertNotEqual(protectedData, plaintext)
        XCTAssertEqual(unprotectedData, plaintext)
        XCTAssertNotNil(
            keychain.values[
                "\(KeychainSessionDataProtector.service)::\(KeychainSessionDataProtector.account)"
            ]
        )
    }

    func testKeychainProtectorReadsPlaintextLegacyPayloads() throws {
        let protector = KeychainSessionDataProtector(keychainService: MockKeychainService())
        let legacyData = Data(#"{"id":"legacy"}"#.utf8)

        XCTAssertEqual(try protector.unprotect(legacyData), legacyData)
    }
}
