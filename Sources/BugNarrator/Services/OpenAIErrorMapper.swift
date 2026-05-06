import Foundation

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

    private static func parseRetryAfter(from headers: [AnyHashable: Any]?) -> TimeInterval? {
        guard let retryValue = headers?["Retry-After"] as? String ?? headers?["retry-after"] as? String else {
            return nil
        }
        return TimeInterval(retryValue)
    }

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
