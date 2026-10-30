import Foundation

/// Refuses a redirect that would move a request to a plaintext remote host.
///
/// `requireEncryptedTransport` looks at the URL of the request it builds. A
/// redirect is a second request that the guard never sees, and CFNetwork
/// follows redirects on its own: an `https` base URL that answers with a 307
/// to an `http` URL would put the issue content on the wire in cleartext,
/// with the Basic-auth credentials attached.
final class JiraTransportRedirectPolicy: NSObject, URLSessionTaskDelegate {
    /// Whether a redirect to `url` may be followed.
    ///
    /// A redirect to plaintext HTTP at a remote host would send the Basic-auth
    /// credentials and the issue content in the clear. A redirect that stays
    /// on https, or that goes to a local address, is fine.
    static func mayFollow(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "http" else {
            return true
        }
        // A plaintext URL without a host is a host the app cannot check, so it
        // is refused like any other one it cannot vouch for.
        guard let host = url.host else { return false }
        return SettingsStore.isLocalEndpointHost(host)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard Self.mayFollow(request.url) else {
            DiagnosticsLogger(category: .export).error(
                "export_redirect_refused",
                "Refused a redirect to a plaintext remote host: \(request.url?.host ?? "unknown")"
            )
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}

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
    ///
    /// Refuses to attach the credentials to a plaintext remote host: the Jira
    /// base URL is typed by the user and a self-hosted Jira on plain HTTP is
    /// common, so this is the last point where the account email, the API token
    /// and the issue content can be kept off the wire in the clear.
    func authenticatedRequest(
        url: URL,
        httpMethod: String,
        email: String,
        apiToken: String,
        includesJSONContentType: Bool
    ) throws -> URLRequest {
        try Self.requireEncryptedTransport(url)

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

    /// Refuses a request that would send Basic-auth credentials over plaintext
    /// HTTP to a host outside the machine. Loopback, private-range and
    /// link-local addresses stay allowed: that traffic never leaves the
    /// machine or the trusted local network. A name the app cannot check — a
    /// `.local` name, a single-label name, a numeric address — is not local.
    private static func requireEncryptedTransport(_ url: URL) throws {
        guard url.scheme?.lowercased() == "http" else {
            return
        }
        // A plaintext URL the app cannot check is refused. A host it cannot
        // even name is not one it can vouch for either.
        guard let host = url.host, SettingsStore.isLocalEndpointHost(host) else {
            // The refusal is built the same way the settings warning builds
            // it, so the export path and the settings screen cannot describe
            // one host differently. A host the app parsed and found to be
            // public is a remote host; a host it could not parse is one it
            // cannot check as a local address.
            throw AppError.exportConfigurationIncompatible(
                SettingsStore.plaintextTransportRefusal(
                    host: url.host,
                    subject: "This Jira URL",
                    secret: "email, API token and issue content",
                    localNoun: "server"
                )
            )
        }
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

        // A redirect the app did not follow: either the policy refused it, or
        // it pointed somewhere the transport rule would not allow.
        if (300..<400).contains(statusCode) {
            return .exportConfigurationIncompatible(
                "Jira answered with a redirect (HTTP \(statusCode)) that BugNarrator did not follow. "
                + "A redirect to a plaintext remote host would send the account email, the API token "
                + "and the issue content in the clear. Use the final https:// URL of your Jira site."
            )
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
