import Foundation

actor JiraExportProvider {
    let session: URLSession
    let receiptStore: any ExportReceiptStoring
    let retryConfiguration: ExportRetryConfiguration
    let logger = DiagnosticsLogger(category: .export)
    let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(
        session: URLSession? = nil,
        receiptStore: any ExportReceiptStoring = ExportReceiptStore(),
        retryConfiguration: ExportRetryConfiguration = .default,
        sessionConfiguration: URLSessionConfiguration? = nil
    ) {
        if let session {
            self.session = session
        } else {
            // A caller can hand in the configuration so that a test can drive
            // the session this provider builds, rather than a session of its
            // own that would not carry the redirect policy.
            let configuration = sessionConfiguration ?? URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            // The delegate refuses a redirect to a plaintext remote host: the
            // guard in `requireEncryptedTransport` sees the request the app
            // builds, not the one a redirect would send.
            self.session = URLSession(
                configuration: configuration,
                delegate: JiraTransportRedirectPolicy(),
                delegateQueue: nil
            )
        }
        self.receiptStore = receiptStore
        self.retryConfiguration = retryConfiguration
    }

    /// Builds the `project = "KEY"` JQL clause with the project key quoted and
    /// backslash/quote-escaped. Jira accepts a quoted project key, so quoting is
    /// behaviour-preserving for normal keys while neutralizing a malformed or
    /// operator-bearing key value before it reaches the JQL parser.
    static func jqlProjectClause(_ projectKey: String) -> String {
        let escaped = projectKey
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "project = \"\(escaped)\""
    }

}

