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
        let message = decodeAPIError(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
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

    private static func decodeAPIError(from data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIErrorPayload
}

private struct APIErrorPayload: Decodable {
    let message: String
}
