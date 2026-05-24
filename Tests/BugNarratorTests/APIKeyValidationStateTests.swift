import XCTest
@testable import BugNarrator

final class APIKeyValidationStateTests: XCTestCase {
    func testIdleAndValidatingDoNotExposeMessages() {
        XCTAssertNil(APIKeyValidationState.idle.message)
        XCTAssertNil(APIKeyValidationState.validating.message)
        XCTAssertFalse(APIKeyValidationState.idle.isFailure)
        XCTAssertFalse(APIKeyValidationState.validating.isFailure)
    }

    func testSuccessAndFailureExposeAssociatedMessages() {
        XCTAssertEqual(APIKeyValidationState.success("Key accepted.").message, "Key accepted.")
        XCTAssertEqual(APIKeyValidationState.failure("Key rejected.").message, "Key rejected.")
        XCTAssertFalse(APIKeyValidationState.success("Key accepted.").isFailure)
        XCTAssertTrue(APIKeyValidationState.failure("Key rejected.").isFailure)
    }
}
