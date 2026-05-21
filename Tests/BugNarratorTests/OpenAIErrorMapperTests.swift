import XCTest
@testable import BugNarrator

final class OpenAIErrorMapperTests: XCTestCase {
    func testParseRetryAfterAcceptsCaseInsensitiveHeaderName() {
        let headers: [AnyHashable: Any] = ["RETRY-AFTER": "12"]
        XCTAssertEqual(OpenAIErrorMapper.parseRetryAfter(from: headers), 12)
    }

    func testParseRetryAfterFloorsZeroAtOneSecond() {
        let headers: [AnyHashable: Any] = ["Retry-After": "0"]
        XCTAssertEqual(OpenAIErrorMapper.parseRetryAfter(from: headers), 1)
    }

    func testParseRetryAfterFloorsNegativeValueAtOneSecond() {
        let headers: [AnyHashable: Any] = ["Retry-After": "-5"]
        XCTAssertEqual(OpenAIErrorMapper.parseRetryAfter(from: headers), 1)
    }

    func testParseRetryAfterReturnsSecondsForNumericValue() {
        let headers: [AnyHashable: Any] = ["Retry-After": "30"]
        XCTAssertEqual(OpenAIErrorMapper.parseRetryAfter(from: headers), 30)
    }

    func testParseRetryAfterParsesHTTPDateFormat() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let later = now.addingTimeInterval(15)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let headers: [AnyHashable: Any] = ["Retry-After": formatter.string(from: later)]

        let parsed = OpenAIErrorMapper.parseRetryAfter(from: headers, now: now)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!, 15, accuracy: 1.0)
    }

    func testParseRetryAfterReturnsNilForMissingHeader() {
        XCTAssertNil(OpenAIErrorMapper.parseRetryAfter(from: nil))
        XCTAssertNil(OpenAIErrorMapper.parseRetryAfter(from: [:]))
    }

    func testParseRetryAfterReturnsNilForUnparseableValue() {
        let headers: [AnyHashable: Any] = ["Retry-After": "soon-ish"]
        XCTAssertNil(OpenAIErrorMapper.parseRetryAfter(from: headers))
    }

    func testMapResponseHonorsCaseInsensitiveRetryAfter() {
        let result = OpenAIErrorMapper.mapResponse(
            statusCode: 429,
            data: Data(),
            fallback: AppError.transcriptionFailure,
            responseHeaders: ["RETRY-AFTER": "0"]
        )

        guard case .rateLimited(let retryAfter) = result else {
            return XCTFail("Expected .rateLimited, got \(result)")
        }
        XCTAssertEqual(retryAfter, 1, "Zero Retry-After should be floored at 1s instead of producing an immediate retry loop.")
    }
}
