import LocalAuthentication
import XCTest
@testable import BugNarrator

final class KeychainServiceTests: XCTestCase {
    func testXCTestEnvironmentBypassesSystemKeychain() {
        XCTAssertTrue(
            KeychainService.shouldBypassSystemKeychain(
                environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
            )
        )
    }

    func testAdHocBuildBypassesSystemKeychain() {
        // When running from Xcode (ad-hoc signed), hasStableCodeSigningIdentity is false,
        // so shouldBypassSystemKeychain returns true even with an empty environment.
        // This test verifies the XCTest env var path is sufficient on its own.
        XCTAssertTrue(
            KeychainService.shouldBypassSystemKeychain(
                environment: ["XCTestBundlePath": "/tmp/Tests.xctest"]
            )
        )
        XCTAssertTrue(
            KeychainService.shouldBypassSystemKeychain(
                environment: ["XCTestSessionIdentifier": "test-session"]
            )
        )
    }

    func testNonInteractiveReadQueryDisablesKeychainUI() {
        let query = KeychainService.makeReadQuery(
            forService: "BugNarrator.OpenAI",
            account: "openai-api-key",
            allowInteraction: false
        )

        let context = query[kSecUseAuthenticationContext] as? LAContext

        XCTAssertEqual(query[kSecAttrService] as? String, "BugNarrator.OpenAI")
        XCTAssertEqual(query[kSecAttrAccount] as? String, "openai-api-key")
        XCTAssertEqual(context?.interactionNotAllowed, true)
        XCTAssertNil(query[kSecUseAuthenticationUI])
    }

    func testInteractiveReadQueryDoesNotForceAuthenticationUIFailure() {
        let query = KeychainService.makeReadQuery(
            forService: "BugNarrator.OpenAI",
            account: "openai-api-key",
            allowInteraction: true
        )

        XCTAssertNil(query[kSecUseAuthenticationContext])
        XCTAssertNil(query[kSecUseAuthenticationUI])
    }

    func testWriteQueryRestrictsSecretToUnlockedLocalDevice() {
        let data = Data("fixture-key".utf8)
        let query = KeychainService.makeWriteQuery(
            forService: "BugNarrator.OpenAI",
            account: "openai-api-key",
            data: data
        )

        XCTAssertEqual(query[kSecAttrService] as? String, "BugNarrator.OpenAI")
        XCTAssertEqual(query[kSecAttrAccount] as? String, "openai-api-key")
        XCTAssertEqual(query[kSecAttrAccessible] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(query[kSecValueData] as? Data, data)
    }
}
