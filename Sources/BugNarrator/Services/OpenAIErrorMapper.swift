import Foundation

enum OpenAIEndpointBuilder {
    static func endpoint(for path: String, baseURL: URL) -> URL {
        var pathComponents = path.split(separator: "/").map(String.init)

        if let firstComponent = pathComponents.first,
           baseURL.lastPathComponent.caseInsensitiveCompare(firstComponent) == .orderedSame {
            pathComponents.removeFirst()
        }

        return pathComponents.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }
}

enum OpenAIErrorMapper {
    static func mapResponse(
        statusCode: Int,
        data: Data,
        fallback: (String) -> AppError,
        responseHeaders: [AnyHashable: Any]? = nil
    ) -> AppError {
        let payload = decodeAPIErrorPayload(from: data)
        let message = payload?.message ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let normalizedMessage = message.lowercased()

        if statusCode == 401 {
            if normalizedMessage.contains("revoked") || normalizedMessage.contains("deactivated") {
                return .revokedAPIKey
            }

            return .invalidAPIKey
        }

        if statusCode == 403,
           normalizedMessage.contains("revoked") || normalizedMessage.contains("deactivated") {
            return .revokedAPIKey
        }

        // Before the generic 429 path: a spent account also answers 429, but
        // retrying it can never succeed. New OpenAI accounts ship with no
        // credits, so this is the likeliest outcome of a fresh key's first
        // transcription (#958).
        if (400...499).contains(statusCode),
           indicatesExhaustedQuota(payload: payload, normalizedMessage: normalizedMessage) {
            return .providerQuotaExhausted
        }

        if statusCode == 429 {
            let retryAfter = parseRetryAfter(from: responseHeaders)
            return .rateLimited(retryAfter: retryAfter)
        }

        if (400...499).contains(statusCode) {
            return .openAIRequestRejected(message)
        }

        return fallback(message)
    }

    static func parseRetryAfter(from headers: [AnyHashable: Any]?, now: Date = Date()) -> TimeInterval? {
        guard let retryValue = retryAfterHeaderValue(in: headers) else {
            return nil
        }

        let trimmed = retryValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let seconds = TimeInterval(trimmed) {
            return max(seconds, 1)
        }

        if let date = httpDateFormatter.date(from: trimmed) {
            let interval = date.timeIntervalSince(now)
            return max(interval, 1)
        }

        return nil
    }

    private static func retryAfterHeaderValue(in headers: [AnyHashable: Any]?) -> String? {
        guard let headers else {
            return nil
        }

        for (key, value) in headers {
            guard let name = key as? String else {
                continue
            }
            if name.caseInsensitiveCompare("Retry-After") == .orderedSame,
               let stringValue = value as? String {
                return stringValue
            }
        }

        return nil
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    static func mapTransportError(_ error: Error, fallback: (String) -> AppError) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .networkTimeout
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return .networkFailure
            default:
                break
            }
        }

        return fallback(error.localizedDescription)
    }

    /// Deliberately narrow. A genuine rate-limit message can mention "quota" or
    /// "billing" in passing, and misreading one as a spent account would strip
    /// the retry that would have succeeded — so this matches the structured
    /// `code`/`type` first and only falls back to unambiguous phrases.
    static func indicatesExhaustedQuota(payload: APIErrorPayload?, normalizedMessage: String) -> Bool {
        if let code = payload?.code?.lowercased(), quotaCodes.contains(code) {
            return true
        }

        if let type = payload?.type?.lowercased(), quotaCodes.contains(type) {
            return true
        }

        return normalizedMessage.contains("insufficient_quota")
            || normalizedMessage.contains("exceeded your current quota")
            || normalizedMessage.contains("billing hard limit")
    }

    private static let quotaCodes: Set<String> = [
        "insufficient_quota",
        "billing_hard_limit_reached",
        "quota_exceeded"
    ]

    private static func decodeAPIErrorPayload(from data: Data) -> APIErrorPayload? {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

struct APIErrorPayload: Decodable {
    let message: String
    let type: String?
    let code: String?

    /// `message` stays required so an undecodable body still falls back to the
    /// HTTP status text, exactly as before. `type`/`code` are best-effort:
    /// some OpenAI-compatible servers return `code` as a number, and letting
    /// that throw would discard the message too.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        type = try? container.decode(String.self, forKey: .type)
        code = try? container.decode(String.self, forKey: .code)
    }

    private enum CodingKeys: String, CodingKey {
        case message
        case type
        case code
    }
}
