import XCTest
@testable import BugNarrator

final class OpenAIErrorMapperTests: XCTestCase {
    func testEndpointBuilderDoesNotDuplicateVersionPath() {
        let endpoint = OpenAIEndpointBuilder.endpoint(
            for: "v1/audio/transcriptions",
            baseURL: URL(string: "http://localhost:1234/v1")!
        )

        XCTAssertEqual(endpoint.absoluteString, "http://localhost:1234/v1/audio/transcriptions")
    }

    func testEndpointBuilderPreservesGatewayPathBeforeVersionPath() {
        let endpoint = OpenAIEndpointBuilder.endpoint(
            for: "v1/chat/completions",
            baseURL: URL(string: "https://gateway.example.com/openai/v1")!
        )

        XCTAssertEqual(endpoint.absoluteString, "https://gateway.example.com/openai/v1/chat/completions")
    }

    func testEndpointBuilderAppendsVersionWhenBaseURLIsProviderRoot() {
        let endpoint = OpenAIEndpointBuilder.endpoint(
            for: "v1/models",
            baseURL: URL(string: "https://api.openai.com")!
        )

        XCTAssertEqual(endpoint.absoluteString, "https://api.openai.com/v1/models")
    }

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

    // MARK: - Exhausted quota vs rate limit (#958)

    private func map(statusCode: Int, body: String, headers: [AnyHashable: Any]? = nil) -> AppError {
        OpenAIErrorMapper.mapResponse(
            statusCode: statusCode,
            data: Data(body.utf8),
            fallback: { .transcriptionFailure($0) },
            responseHeaders: headers
        )
    }

    /// The real OpenAI body for a new account with no credits — the likeliest
    /// outcome of a fresh key's first transcription.
    func testInsufficientQuotaMapsToQuotaExhaustedNotRateLimited() {
        let body = """
        {"error":{"message":"You exceeded your current quota, please check your plan and billing details.","type":"insufficient_quota","param":null,"code":"insufficient_quota"}}
        """

        XCTAssertEqual(map(statusCode: 429, body: body), .providerQuotaExhausted)
    }

    /// A spent account answers 429 with a Retry-After like any other 429.
    /// Honouring it would back off and retry something that can never succeed.
    func testExhaustedQuotaWinsOverAPresentRetryAfterHeader() {
        let body = """
        {"error":{"message":"Quota exceeded.","type":"insufficient_quota","code":"insufficient_quota"}}
        """

        XCTAssertEqual(
            map(statusCode: 429, body: body, headers: ["Retry-After": "30"]),
            .providerQuotaExhausted,
            "A Retry-After on a spent account is not a reason to retry."
        )
    }

    func testGenuineRateLimitKeepsRetryingBehavior() {
        let body = """
        {"error":{"message":"Rate limit reached for gpt-4o-mini in organization org-x on tokens per min (TPM): Limit 200000.","type":"tokens","code":"rate_limit_exceeded"}}
        """

        XCTAssertEqual(
            map(statusCode: 429, body: body, headers: ["Retry-After": "20"]),
            .rateLimited(retryAfter: 20),
            "Genuine rate limits must keep the existing retry path."
        )
    }

    /// The guard against over-matching. A rate-limit message that happens to
    /// say "quota" must not be reclassified — doing so would strip a retry that
    /// would have succeeded.
    func testRateLimitMentioningQuotaInPassingIsStillARateLimit() {
        let body = """
        {"error":{"message":"Rate limit reached. Your quota resets in 60 seconds.","type":"requests","code":"rate_limit_exceeded"}}
        """

        XCTAssertEqual(map(statusCode: 429, body: body), .rateLimited(retryAfter: nil))
    }

    /// Some OpenAI-compatible servers return `code` as a number. Decoding must
    /// not throw away the message when that happens.
    func testNumericCodeFieldDoesNotDiscardTheMessage() {
        let body = """
        {"error":{"message":"Model not found.","type":"invalid_request_error","code":404}}
        """

        XCTAssertEqual(map(statusCode: 400, body: body), .openAIRequestRejected("Model not found."))
    }

    func testQuotaSignalIsHonoredOnNon429ClientErrors() {
        let body = """
        {"error":{"message":"Billing hard limit has been reached.","type":"billing_hard_limit_reached"}}
        """

        XCTAssertEqual(map(statusCode: 400, body: body), .providerQuotaExhausted)
    }

    func testUnauthorizedStillWinsOverAQuotaSignal() {
        let body = """
        {"error":{"message":"Incorrect API key provided.","type":"invalid_request_error","code":"invalid_api_key"}}
        """

        XCTAssertEqual(map(statusCode: 401, body: body), .invalidAPIKey)
    }

    // MARK: - Downstream behavior

    /// Non-retry is enforced upstream of this assertion: `TranscriptionClient`
    /// backs off only for `.rateLimited`, and `shouldRetryTransientFailure`
    /// allowlists only the two network cases. Both are `private`, so the
    /// testable guarantee is the one that actually gates them — the mapper
    /// never returns `.rateLimited` for a spent account, covered by the cases
    /// above. This test pins the other half: the recording is still preserved.
    func testQuotaExhaustedStillPreservesTheRecording() {
        // Before #958 a spent account surfaced as .rateLimited, which preserved
        // the recording as a retryable pending transcription. Losing that would
        // be a regression for exactly the first-run user this ticket is about.
        XCTAssertEqual(
            PendingTranscriptionFailureReason(appError: .providerQuotaExhausted),
            .providerQuotaExhausted
        )
        XCTAssertEqual(
            PendingTranscriptionFailureReason.providerQuotaExhausted.appError,
            .providerQuotaExhausted
        )
    }

    func testQuotaExhaustedMessageNamesTheFixAndDoesNotSayRateLimit() {
        let message = AppError.providerQuotaExhausted.userMessage(for: .openAI)

        XCTAssertTrue(message.lowercased().contains("credits"), message)
        XCTAssertFalse(
            message.lowercased().contains("rate limit"),
            "This is the copy the bug was about — it must not read as a transient limit."
        )
        XCTAssertNotEqual(AppError.providerQuotaExhausted.statusTitle, "Network Issue")
    }

}
