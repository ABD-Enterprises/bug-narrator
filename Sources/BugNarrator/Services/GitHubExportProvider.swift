import Foundation

actor GitHubExportProvider {
    let session: URLSession
    let receiptStore: any ExportReceiptStoring
    private let retryConfiguration: ExportRetryConfiguration
    private let logger = DiagnosticsLogger(category: .export)
    let annotationRenderer = IssueScreenshotAnnotationRenderer()

    init(
        session: URLSession? = nil,
        receiptStore: any ExportReceiptStoring = ExportReceiptStore(),
        retryConfiguration: ExportRetryConfiguration = .default
    ) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 90
            self.session = URLSession(configuration: configuration)
        }
        self.receiptStore = receiptStore
        self.retryConfiguration = retryConfiguration
    }


    func export(
        issues: [ExtractedIssue],
        session reviewSession: TranscriptSession,
        configuration: GitHubExportConfiguration
    ) async throws -> [ExportResult] {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "GitHub export requires a personal access token, repository owner, and repository name."
            )
        }

        logger.info(
            "github_export_requested",
            "Exporting selected issues to GitHub.",
            metadata: [
                "issue_count": "\(issues.count)",
                "repository": "\(configuration.owner)/\(configuration.repository)",
                "session_id": reviewSession.id.uuidString
            ]
        )

        var results: [ExportResult] = []

        for issue in issues {
            let fingerprint = TrackerExportFingerprint.make(
                destination: .github,
                targetIdentity: configuration.targetIdentity,
                sessionID: reviewSession.id,
                issueID: issue.id
            )

            if let existingResult = try await existingExportResult(
                fingerprint: fingerprint,
                sourceIssueID: issue.id,
                configuration: configuration
            ) {
                results.append(existingResult)
                continue
            }

            try await receiptStore.markPending(
                fingerprint: fingerprint,
                sourceIssueID: issue.id,
                destination: .github,
                targetIdentity: configuration.targetIdentity
            )

            let request = try makeURLRequest(
                issue: issue,
                session: reviewSession,
                configuration: configuration,
                exportFingerprint: fingerprint
            )

            let result = try await createWithRetry(
                issue: issue,
                fingerprint: fingerprint,
                request: request,
                configuration: configuration,
                successfulCount: results.count
            )
            results.append(result)
        }

        logger.info(
            "github_export_completed",
            "Finished exporting issues to GitHub.",
            metadata: [
                "issue_count": "\(results.count)",
                "repository": "\(configuration.owner)/\(configuration.repository)"
            ]
        )
        return results
    }

    func validate(configuration: GitHubExportConfiguration) async throws {
        guard configuration.isComplete else {
            throw AppError.exportConfigurationMissing(
                "GitHub export requires a personal access token, repository owner, and repository name."
            )
        }

        let request = try makeRepositoryValidationRequest(configuration: configuration)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.exportFailure("GitHub returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw mapGitHubError(statusCode: httpResponse.statusCode, data: data, configuration: configuration)
        }

        let repository = try JSONDecoder().decode(GitHubRepositoryValidationResponse.self, from: data)
        guard repository.hasIssues else {
            throw AppError.exportFailure(
                "GitHub Issues are disabled for \(configuration.owner)/\(configuration.repository)."
            )
        }

        if let permissions = repository.permissions,
           !permissions.canCreateIssues {
            throw AppError.exportFailure(
                "The GitHub token can read \(configuration.owner)/\(configuration.repository), but it cannot create issues there."
            )
        }
    }


    func makeURLRequest(
        issue: ExtractedIssue,
        session reviewSession: TranscriptSession,
        configuration: GitHubExportConfiguration,
        exportFingerprint: String? = nil
    ) throws -> URLRequest {
        let endpoint = issueEndpoint(configuration: configuration)

        var request = authenticatedRequest(
            url: endpoint,
            httpMethod: "POST",
            token: configuration.token,
            includesJSONContentType: true
        )
        request.httpBody = try JSONEncoder().encode(
            GitHubIssueRequest(
                title: issue.title,
                body: try makeIssueBody(
                    issue: issue,
                    session: reviewSession,
                    exportFingerprint: exportFingerprint
                ),
                labels: configuration.labels.isEmpty ? nil : configuration.labels
            )
        )
        return request
    }

    private func makeRepositoryValidationRequest(
        configuration: GitHubExportConfiguration
    ) throws -> URLRequest {
        return authenticatedRequest(
            url: repositoryEndpoint(configuration: configuration),
            httpMethod: "GET",
            token: configuration.token,
            includesJSONContentType: false
        )
    }






    /// Creates one issue with bounded retry. Transient failures (network / 5xx /
    /// 429) are retried with backoff, but ONLY after a marker reconciliation
    /// confirms the issue was not already created — so a created-but-unacked issue
    /// is never duplicated. The pending receipt is kept across transient retries;
    /// it is cleared only on a confirmed permanent failure.
    private static let retryContext = TrackerExportRetryContext(
        displayName: "GitHub",
        destination: .github,
        exportedLogEvent: "github_issue_exported",
        failedLogEvent: "github_export_failed",
        reconciliationFailedLogEvent: "github_export_reconciliation_failed"
    )

    private func createWithRetry(
        issue: ExtractedIssue,
        fingerprint: String,
        request: URLRequest,
        configuration: GitHubExportConfiguration,
        successfulCount: Int
    ) async throws -> ExportResult {
        try await TrackerExportSupport.runCreateWithRetry(
            issueID: issue.id,
            fingerprint: fingerprint,
            targetIdentity: configuration.targetIdentity,
            successfulCount: successfulCount,
            configuration: retryConfiguration,
            receiptStore: receiptStore,
            logger: logger,
            context: Self.retryContext,
            attemptCreate: { await self.attemptCreate(request, configuration: configuration) },
            reconcile: {
                try await self.reconcilePendingExport(
                    fingerprint: fingerprint,
                    sourceIssueID: issue.id,
                    configuration: configuration
                )
            }
        )
    }

    private func attemptCreate(
        _ request: URLRequest,
        configuration: GitHubExportConfiguration
    ) async -> ExportCreateOutcome {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .permanent(.exportFailure("GitHub returned an invalid response."))
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let retryAfter = TrackerExportSupport.retryAfterSeconds(from: httpResponse)
                let mapped = mapGitHubError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    configuration: configuration,
                    retryAfterSeconds: retryAfter
                )
                return TrackerExportSupport.isTransientStatus(httpResponse.statusCode)
                    ? .transient(mapped, retryAfterSeconds: retryAfter)
                    : .permanent(mapped)
            }

            do {
                let payload = try JSONDecoder().decode(GitHubIssueResponse.self, from: data)
                return .success(remoteIdentifier: "#\(payload.number)", remoteURL: payload.htmlURL)
            } catch {
                // A 2xx whose body we cannot read is a created-but-unacknowledged
                // issue: GitHub accepted the create, but we could not parse the
                // identifier. Treat it as ambiguous/transient — NOT permanent — so
                // the pending receipt is preserved and reconciliation-by-marker
                // resolves it, instead of clearing the receipt and risking a
                // duplicate on a later export.
                return .transient(.exportFailure("GitHub returned an unreadable response."), retryAfterSeconds: nil)
            }
        } catch {
            // Network/transport failure — retryable.
            let mapped = OpenAIErrorMapper.mapTransportError(error, fallback: AppError.exportFailure)
            return .transient(mapped, retryAfterSeconds: nil)
        }
    }










}
