import Foundation

extension JiraExportProvider {
    func decodeJiraPayload<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        description: String
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AppError.exportFailure(
                "Jira returned \(description) in an unexpected format. \(Self.decodingFailureMessage(error))"
            )
        }
    }

    private static func decodingFailureMessage(_ error: Error) -> String {
        guard case DecodingError.keyNotFound(let key, _) = error else {
            return error.localizedDescription
        }

        return "Missing field '\(key.stringValue)'."
    }

    private func basicAuthValue(email: String, apiToken: String) -> String {
        let rawValue = "\(email):\(apiToken)"
        return Data(rawValue.utf8).base64EncodedString()
    }

    /// Builds a Jira request URL from the configured base URL, appending the
    /// given path and optional query items. Throws a typed export error instead
    /// of trapping when the base URL cannot be expressed as URL components.
    func jiraRequestURL(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw AppError.exportFailure(
                "Could not build a Jira request URL from the configured base URL."
            )
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AppError.exportFailure(
                "Could not build a Jira request URL from the configured base URL."
            )
        }

        return url
    }

    /// Produces a Jira REST request with the shared Basic auth, Accept, and
    /// User-Agent headers applied. Pass `includesJSONContentType` for requests
    /// that carry a JSON body.
    func authenticatedRequest(
        url: URL,
        httpMethod: String,
        email: String,
        apiToken: String,
        includesJSONContentType: Bool
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue(
            "Basic \(basicAuthValue(email: email, apiToken: apiToken))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if includesJSONContentType {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("BugNarrator", forHTTPHeaderField: "User-Agent")
        return request
    }

    func mapJiraError(
        statusCode: Int,
        data: Data,
        configuration: JiraExportConfiguration,
        retryAfterSeconds: Int? = nil
    ) -> AppError {
        let message = decodeJiraMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let normalizedMessage = message.lowercased()

        // 429 is a rate limit, not an auth failure; map it explicitly.
        if statusCode == 429 || normalizedMessage.contains("rate limit") {
            return .exportFailure("Jira rate limited the request.\(TrackerExportSupport.retryAfterSuffix(retryAfterSeconds))")
        }

        if statusCode == 401 || statusCode == 403 {
            return .exportFailure("Jira rejected the credentials for project \(configuration.projectKey).")
        }

        if statusCode == 404 {
            return .exportFailure("Jira could not find the configured site or project \(configuration.projectKey).")
        }

        if statusCode == 400 {
            return .exportFailure("Jira rejected the issue payload: \(message)")
        }

        return .exportFailure("Jira returned \(statusCode): \(message)")
    }

    private func decodeJiraMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(JiraErrorResponse.self, from: data) {
            let messages = payload.errorMessages + payload.errors.values
            return messages.joined(separator: " ")
        }

        return nil
    }
}

struct JiraErrorResponse: Decodable {
    let errorMessages: [String]
    let errors: [String: String]
}
