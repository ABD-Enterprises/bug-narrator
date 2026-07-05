import Foundation
@testable import BugNarrator

func makeSampleTranscriptSession(index: Int) -> TranscriptSession {
    TranscriptSession(
        id: UUID(),
        createdAt: Date(timeIntervalSince1970: TimeInterval(index * 60)),
        transcript: "Transcript \(index)",
        duration: TimeInterval(index),
        model: "whisper-1",
        languageHint: nil,
        prompt: nil
    )
}

func waitUntil(
    timeoutNanoseconds: UInt64 = 500_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() {
            return
        }

        try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
    }
}

func requestBodyData(from request: URLRequest) throws -> Data {
    if let httpBody = request.httpBody {
        return httpBody
    }

    guard let stream = request.httpBodyStream else {
        throw NSError(domain: "BugNarratorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Request body was missing."])
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let readCount = stream.read(buffer, maxLength: bufferSize)
        if readCount < 0 {
            throw stream.streamError ?? NSError(
                domain: "BugNarratorTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Request body stream could not be read."]
            )
        }

        if readCount == 0 {
            break
        }

        data.append(buffer, count: readCount)
    }

    return data
}
