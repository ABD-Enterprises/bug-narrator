import Foundation

/// Bounds structured service replies while receiving them, including chunked
/// responses that omit or understate Content-Length.
enum BoundedHTTPResponseReader {
    static let maximumBodyBytes = 16 * 1_024 * 1_024
    static let maximumErrorBytes = 64 * 1_024

    struct ReplyTooLarge: LocalizedError {
        var errorDescription: String? {
            "The server reply exceeded BugNarrator’s size limit. The request was stopped to protect memory."
        }
    }

    static func data(
        for request: URLRequest,
        using session: URLSession,
        delegate: (any URLSessionTaskDelegate)? = nil,
        maximumBytes: Int = maximumBodyBytes
    ) async throws -> (Data, URLResponse) {
        guard maximumBytes > 0 else { throw ReplyTooLarge() }
        let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
        defer { bytes.task.cancel() }
        let succeeded = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        let limit = succeeded ? maximumBytes : min(maximumBytes, maximumErrorBytes)
        guard response.expectedContentLength <= Int64(limit) else { throw ReplyTooLarge() }
        var payload = Data()
        if response.expectedContentLength > 0 {
            payload.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard payload.count < limit else { throw ReplyTooLarge() }
            if payload.count % 4_096 == 0 { try Task.checkCancellation() }
            payload.append(byte)
        }
        try Task.checkCancellation()
        return (payload, response)
    }

    static func data(
        from url: URL,
        using session: URLSession,
        maximumBytes: Int = maximumBodyBytes
    ) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url), using: session, maximumBytes: maximumBytes)
    }
}
