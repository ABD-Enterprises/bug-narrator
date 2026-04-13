import Foundation
import XCTest
@testable import BugNarrator

final class TranscriptionClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testMakeURLRequestIncludesMultipartFieldsAndAuthorization() async throws {
        let fileURL = try makeAudioFile(named: "request", contents: "audio-data")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let client = TranscriptionClient(session: makeMockURLSession())
        let request = try await client.makeURLRequest(
            fileURL: fileURL,
            apiKey: "fixture-openai-key",
            request: TranscriptionRequest(
                model: "whisper-1",
                languageHint: "en",
                prompt: "Review the UI flow"
            )
        )

        let body = try requestBodyData(from: request)
        let bodyString = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-openai-key")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        XCTAssertTrue(bodyString.contains("name=\"model\""))
        XCTAssertTrue(bodyString.contains("whisper-1"))
        XCTAssertTrue(bodyString.contains("name=\"language\""))
        XCTAssertTrue(bodyString.contains("name=\"prompt\""))
        XCTAssertTrue(bodyString.contains("filename=\"\(fileURL.lastPathComponent)\""))
        XCTAssertTrue(bodyString.contains("audio-data"))
    }

    func testTranscribeRejectsEmptyAudioFileBeforeMakingNetworkCall() async throws {
        let fileURL = try makeAudioFile(named: "empty", contents: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.requestHandler = { _ in
            XCTFail("The network should not be called for an empty file.")
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        do {
            _ = try await client.transcribe(
                fileURL: fileURL,
                apiKey: "fixture-openai-key",
                request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
            )
            XCTFail("Expected an error for an empty audio file.")
        } catch let error as AppError {
            guard case .transcriptionFailure(let message) = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }

            XCTAssertEqual(message, "The recorded audio file was empty.")
        }
    }

    func testTranscribeMapsAPIErrorResponse() async throws {
        let fileURL = try makeAudioFile(named: "api-error", contents: "audio-data")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"error":{"message":"Invalid API key."}}"#.utf8)
            return (response, data)
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        do {
            _ = try await client.transcribe(
                fileURL: fileURL,
                apiKey: "bad-key",
                request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
            )
            XCTFail("Expected an API error.")
        } catch let error as AppError {
            guard case .invalidAPIKey = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }
        }
    }

    func testValidateAPIKeyMakesBearerRequest() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-openai-key")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"data":[]}"#.utf8))
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        try await client.validateAPIKey("fixture-openai-key")
    }

    func testValidateAPIKeyMapsRevokedKeyResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"error":{"message":"This API key has been revoked."}}"#.utf8)
            return (response, data)
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        do {
            try await client.validateAPIKey("revoked-key")
            XCTFail("Expected a revoked key error.")
        } catch let error as AppError {
            guard case .revokedAPIKey = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }
        }
    }

    func testTranscribeMapsNetworkTimeout() async throws {
        let fileURL = try makeAudioFile(named: "timeout", contents: "audio-data")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        do {
            _ = try await client.transcribe(
                fileURL: fileURL,
                apiKey: "fixture-openai-key",
                request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
            )
            XCTFail("Expected a timeout error.")
        } catch let error as AppError {
            guard case .networkTimeout = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }
        }
    }

    func testTranscribeRejectsEmptyTranscriptPayload() async throws {
        let fileURL = try makeAudioFile(named: "empty-transcript", contents: "audio-data")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data(#"{"text":"   ","segments":[]}"#.utf8)
            return (response, data)
        }

        let client = TranscriptionClient(session: makeMockURLSession())

        do {
            _ = try await client.transcribe(
                fileURL: fileURL,
                apiKey: "fixture-openai-key",
                request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
            )
            XCTFail("Expected an empty transcript error.")
        } catch let error as AppError {
            guard case .emptyTranscript = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }
        }
    }

    private func makeAudioFile(named name: String, contents: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-TranscriptionTests-\(name)")
            .appendingPathExtension("m4a")
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }
}
