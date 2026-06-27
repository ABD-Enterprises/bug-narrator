import Foundation

actor IssueExtractionService: IssueExtracting {
    static let defaultTimeoutDuration: Duration = .seconds(10)

    private let session: URLSession
    private let timeoutDuration: Duration
    private let logger = DiagnosticsLogger(category: .transcription)

    init(session: URLSession? = nil, timeoutDuration: Duration = IssueExtractionService.defaultTimeoutDuration) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration)
        }
        self.timeoutDuration = timeoutDuration
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String,
        apiBaseURL: URL = URL(string: "https://api.openai.com")!
    ) async throws -> IssueExtractionResult {
        logger.info(
            "issue_extraction_request_started",
            "Sending the transcript to OpenAI for issue extraction.",
            metadata: [
                "session_id": reviewSession.id.uuidString,
                "model": model,
                "marker_count": "\(reviewSession.markerCount)",
                "screenshot_count": "\(reviewSession.screenshotCount)"
            ]
        )
        do {
            let request = try IssueExtractionRequestBuilder.makeRequest(
                endpoint: OpenAIEndpointBuilder.endpoint(for: "v1/chat/completions", baseURL: apiBaseURL),
                reviewSession: reviewSession,
                apiKey: apiKey,
                model: model
            )

            let result = try await withThrowingTaskGroup(of: IssueExtractionResult.self) { group in
                let session = self.session
                let timeoutDuration = self.timeoutDuration

                group.addTask {
                    try await Self.performRequest(request, using: session, reviewSession: reviewSession)
                }

                group.addTask {
                    try await Task.sleep(for: timeoutDuration)
                    throw AppError.issueExtractionFailure(Self.timeoutFailureMessage(for: timeoutDuration))
                }

                guard let firstResult = try await group.next() else {
                    throw AppError.issueExtractionFailure("The extraction response was empty.")
                }

                group.cancelAll()
                return firstResult
            }

            logger.info(
                "issue_extraction_request_succeeded",
                "OpenAI returned extracted review issues.",
                metadata: [
                    "session_id": reviewSession.id.uuidString,
                    "issue_count": "\(result.issues.count)"
                ]
            )
            return result
        } catch {
            logger.error(
                "issue_extraction_request_failed",
                (error as? AppError)?.userMessage ?? error.localizedDescription,
                metadata: ["session_id": reviewSession.id.uuidString]
            )
            throw OpenAIErrorMapper.mapTransportError(error, fallback: AppError.issueExtractionFailure)
        }
    }

    private static func timeoutFailureMessage(for duration: Duration) -> String {
        "Issue extraction took longer than \(timeoutDisplayText(for: duration)). Retry the extraction or choose a faster model in Settings."
    }

    private static func timeoutDisplayText(for duration: Duration) -> String {
        let components = duration.components
        let rawSeconds = max(
            0,
            Double(components.seconds) + (Double(components.attoseconds) / 1_000_000_000_000_000_000)
        )

        if rawSeconds.rounded() == rawSeconds {
            let wholeSeconds = Int(rawSeconds)
            return "\(wholeSeconds) second\(wholeSeconds == 1 ? "" : "s")"
        }

        let roundedTenths = ceil(rawSeconds * 10) / 10
        return "\(String(format: "%.1f", roundedTenths)) seconds"
    }

    private static func performRequest(
        _ request: URLRequest,
        using session: URLSession,
        reviewSession: TranscriptSession
    ) async throws -> IssueExtractionResult {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.issueExtractionFailure("The server response was invalid.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw OpenAIErrorMapper.mapResponse(
                statusCode: httpResponse.statusCode,
                data: data,
                fallback: AppError.issueExtractionFailure
            )
        }

        return try IssueExtractionResponseParser.parseResult(from: data, session: reviewSession)
    }
}
