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

    func testTranscribeRejectsOversizedAudioFileBeforeMakingNetworkCall() async throws {
        let fileURL = try makeSparseAudioFile(
            named: "oversized",
            byteCount: AudioUploadPolicy.maximumSingleUploadBytes + 1
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        MockURLProtocol.requestHandler = { _ in
            XCTFail("The network should not be called for an oversized file.")
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
            XCTFail("Expected an error for an oversized audio file.")
        } catch let error as AppError {
            guard case .transcriptionFailure(let message) = error else {
                XCTFail("Unexpected app error: \(error)")
                return
            }

            XCTAssertTrue(message.contains("safe upload limit"))
        }
    }

    func testTranscribeSurfacesRepeatedTranscriptQualityFinding() async throws {
        let fileURL = try makeAudioFile(named: "repeated-transcript", contents: "audio-data")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let repeatedText = Array(repeating: "show you how it works", count: 6).joined(separator: " ")
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = try JSONSerialization.data(
                withJSONObject: [
                    "text": repeatedText,
                    "segments": []
                ]
            )
            return (response, data)
        }

        let client = TranscriptionClient(session: makeMockURLSession())
        let result = try await client.transcribe(
            fileURL: fileURL,
            apiKey: "fixture-openai-key",
            request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
        )

        XCTAssertEqual(result.text, repeatedText)
        XCTAssertEqual(result.qualityFindings.map(\.kind), [.repeatedText])
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

    func testTranscribeMergesChunkedResultsAndAdjustsSegmentTimes() async throws {
        let originalFileURL = try makeAudioFile(named: "chunked-original", contents: "audio-data")
        let firstChunkURL = try makeAudioFile(named: "chunk-1", contents: "chunk-one")
        let secondChunkURL = try makeAudioFile(named: "chunk-2", contents: "chunk-two")
        defer { try? FileManager.default.removeItem(at: originalFileURL) }

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1

            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!

            let payload: String
            switch requestCount {
            case 1:
                payload = #"{"text":"First section","segments":[{"start":0,"end":4.5,"text":"First section"}]}"#
            case 2:
                payload = #"{"text":"Second section","segments":[{"start":0.25,"end":3.0,"text":"Second section"}]}"#
            default:
                XCTFail("Unexpected extra transcription request.")
                payload = #"{"text":"","segments":[]}"#
            }

            return (response, Data(payload.utf8))
        }

        let client = TranscriptionClient(
            session: makeMockURLSession(),
            transcriptionChunker: MockTranscriptionChunker(
                chunks: [
                    TranscriptionAudioChunk(fileURL: firstChunkURL, startTime: 0, isTemporary: true),
                    TranscriptionAudioChunk(fileURL: secondChunkURL, startTime: 120, isTemporary: true)
                ]
            )
        )

        let result = try await client.transcribe(
            fileURL: originalFileURL,
            apiKey: "fixture-openai-key",
            request: TranscriptionRequest(model: "whisper-1", languageHint: nil, prompt: nil)
        )

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(result.text, "First section\n\nSecond section")
        XCTAssertEqual(result.segments.map(\.text), ["First section", "Second section"])
        XCTAssertEqual(result.segments.count, 2)
        XCTAssertEqual(result.segments[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(result.segments[0].end, 4.5, accuracy: 0.001)
        XCTAssertEqual(result.segments[1].start, 120.25, accuracy: 0.001)
        XCTAssertEqual(result.segments[1].end, 123.0, accuracy: 0.001)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstChunkURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondChunkURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFileURL.path))
    }

    private func makeAudioFile(named name: String, contents: String) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-TranscriptionTests-\(name)")
            .appendingPathExtension("m4a")
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    private func makeSparseAudioFile(named name: String, byteCount: Int) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-TranscriptionTests-\(name)")
            .appendingPathExtension("m4a")
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(byteCount))
        try handle.close()
        return fileURL
    }
}

private struct MockTranscriptionChunker: TranscriptionChunking {
    let chunks: [TranscriptionAudioChunk]

    func chunks(for fileURL: URL) async throws -> [TranscriptionAudioChunk] {
        chunks
    }
}
