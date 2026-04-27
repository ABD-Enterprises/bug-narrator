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
        XCTAssertFalse(KeychainService.shouldBypassSystemKeychain(environment: [:]))
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
}
