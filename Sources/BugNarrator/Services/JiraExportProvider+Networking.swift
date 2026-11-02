import Foundation

/// Refuses a redirect that would move a request off the origin the user
/// configured, and a redirect that would move it to a plaintext remote host.
///
/// `requireEncryptedTransport` looks at the URL of the request it builds. A
/// redirect is a second request that the guard never sees, and CFNetwork
/// follows redirects on its own: an `https` base URL that answers with a 307
/// to an `http` URL would put the issue content on the wire in cleartext,
/// with the Basic-auth credentials attached. A redirect to another host
/// would put the account email, the API token and the issue content in the
/// hands of a host the user never named.
final class JiraTransportRedirectPolicy: NSObject, URLSessionTaskDelegate {
    /// Why a redirect may not be followed.
    enum Refusal: Equatable {
        /// The redirect pointed at another origin: another host, another
        /// port or another scheme.
        case leavesTheOrigin

        /// The redirect pointed at a plaintext remote host, or at a plaintext
        /// URL without a host.
        case plaintextRemoteHost
    }

    /// The reason a redirect to `url` may not be followed, or nil when it may.
    ///
    /// A redirect to a plaintext remote host is refused first, whatever the
    /// origin it started at: that is the worse of the two cases, and checking
    /// it first keeps it reachable (an `https` answer redirecting to the same
    /// host over `http` is a plaintext redirect, not "another host"). A
    /// redirect that then leaves the origin the request started at is refused
    /// too: the credentials belong to the site the user configured and to
    /// nowhere else. A redirect that stays on the origin is fine, and so is one
    /// to a local address over plaintext - but only when it stays on the
    /// origin too.
    static func refusal(for url: URL?, from original: URL? = nil) -> Refusal? {
        guard let url else { return nil }

        if url.scheme?.lowercased() == "http" {
            // A plaintext URL without a host is a host the app cannot check,
            // so it is refused like any other one it cannot vouch for.
            guard let host = url.host else { return .plaintextRemoteHost }
            if !SettingsStore.isLocalEndpointHost(host) { return .plaintextRemoteHost }
        }

        if let original, !sameOrigin(url, original) {
            return .leavesTheOrigin
        }
        return nil
    }

    /// Whether a redirect to `url` may be followed.
    static func mayFollow(_ url: URL?, from original: URL? = nil) -> Bool {
        refusal(for: url, from: original) == nil
    }

    /// Why the last redirect was refused, so the error can name the reason
    /// instead of guessing at it.
    private let refusalLock = NSLock()
    private var recordedRefusal: Refusal?

    var lastRefusal: Refusal? {
        refusalLock.lock()
        defer { refusalLock.unlock() }
        return recordedRefusal
    }

    private func record(_ refusal: Refusal) {
        refusalLock.lock()
        defer { refusalLock.unlock() }
        recordedRefusal = refusal
    }

    /// What the refusal means, in a sentence.
    static func describe(_ refusal: Refusal) -> String {
        switch refusal {
        case .leavesTheOrigin:
            return "it leaves the configured origin, so the credentials and the issue content would have gone to another host"
        case .plaintextRemoteHost:
            return "it points at a plaintext remote host, so the credentials and the issue content would have gone in the clear"
        }
    }

    /// Whether two URLs name the same origin: the same scheme, the same host
    /// and the same port.
    static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    /// The port the URL addresses, counting the scheme's default when the URL
    /// does not spell one out.
    private static func effectivePort(_ url: URL) -> Int? {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let refusal = Self.refusal(for: request.url, from: task.originalRequest?.url) {
            record(refusal)
            DiagnosticsLogger(category: .export).error(
                "export_redirect_refused",
                "Refused a redirect to \(request.url?.absoluteString ?? "unknown"): \(Self.describe(refusal))"
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

        // A redirect the app did not follow: these are the statuses CFNetwork
        // follows, so the app only sees one when its own policy refused it.
        // 300 is not one of them - RFC 9110 lets it carry a Location header,
        // but CFNetwork does not offer it to the session's delegate, so it
        // arrives as an ordinary response. The other 3xx codes are not
        // redirects either: 304 is a cached response, 305 is deprecated and
        // 306 is unused.
        if [301, 302, 303, 307, 308].contains(statusCode) {
            return .exportConfigurationIncompatible(redirectRefusalMessage(statusCode: statusCode))
        }

        return .exportFailure("Jira returned \(statusCode): \(message)")
    }

    /// The message for a redirect the app refused, naming the reason it was
    /// refused: a redirect to another host would have taken the credentials
    /// and the issue content with it, encrypted or not.
    private func redirectRefusalMessage(statusCode: Int) -> String {
        let reason: String
        switch redirectPolicy.lastRefusal {
        case .leavesTheOrigin:
            reason = "The redirect pointed at another host, so the account email, the API token "
                + "and the issue content would have gone there."
        case .plaintextRemoteHost:
            reason = "The redirect pointed at a plaintext remote host, so the account email, the API "
                + "token and the issue content would have gone in the clear."
        case nil:
            reason = "The redirect pointed somewhere BugNarrator does not send the account email, "
                + "the API token and the issue content."
        }
        return "Jira answered with a redirect (HTTP \(statusCode)) that BugNarrator did not follow. "
            + reason
            + " Use the final https:// URL of your Jira site."
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
