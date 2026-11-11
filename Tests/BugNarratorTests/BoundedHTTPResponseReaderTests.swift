import Foundation
import XCTest
@testable import BugNarrator

final class BoundedHTTPResponseReaderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testExactLimitPreservesTheWholeReply() async throws {
        let fixture = Data("fixture-é".utf8)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, fixture)
        }
        let session = makeMockURLSession()
        defer { session.invalidateAndCancel() }
        let (body, response) = try await BoundedHTTPResponseReader.data(
            for: URLRequest(url: URL(string: "https://provider.example.test/reply")!),
            using: session, maximumBytes: fixture.count)
        XCTAssertEqual(body, fixture)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    func testLengthlessAndMisdeclaredRepliesCannotExceedTheCeiling() async throws {
        for headers: [String: String] in [[:], ["Content-Length": "2"]] {
            MockURLProtocol.requestHandler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!, Data(repeating: 120, count: 4096))
            }
            let session = makeMockURLSession()
            defer { session.invalidateAndCancel() }
            do {
                _ = try await BoundedHTTPResponseReader.data(
                    for: URLRequest(url: URL(string: "https://provider.example.test/reply")!),
                    using: session, maximumBytes: 1024)
                XCTFail("Oversized replies must fail rather than return truncated data")
            } catch is BoundedHTTPResponseReader.ReplyTooLarge {
                // Expected, even when the server omits or understates its length.
            }
        }
    }

    func testDeclaredOversizeAndLargeErrorRepliesAreRefused() async throws {
        for (status, headers, size) in [(200, ["Content-Length": "999999999"], 1), (400, [:], 65537)] {
            MockURLProtocol.requestHandler = { request in
                (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, Data(repeating: 120, count: size))
            }
            let session = makeMockURLSession()
            defer { session.invalidateAndCancel() }
            do {
                _ = try await BoundedHTTPResponseReader.data(
                    for: URLRequest(url: URL(string: "https://provider.example.test/reply")!), using: session)
                XCTFail("Oversized replies must be refused")
            } catch is BoundedHTTPResponseReader.ReplyTooLarge {}
        }
    }

    func testRedirectRefusalStillRunsWithTheStreamingReader() async throws {
        let target = try RedirectServer(location: "http://127.0.0.1:1/unused")
        defer { target.stop() }
        target.serve()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await BoundedHTTPResponseReader.data(
            for: URLRequest(url: URL(string: "http://127.0.0.1:\(target.port)/fixture")!),
            using: session, delegate: SensitiveRequestRedirectPolicy.shared)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 307)
    }
}
