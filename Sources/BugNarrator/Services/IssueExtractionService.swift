import Foundation

actor IssueExtractionService: IssueExtracting {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let session: URLSession
    private let logger = DiagnosticsLogger(category: .transcription)

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 180
            self.session = URLSession(configuration: configuration)
        }
    }

    func extractIssues(
        from reviewSession: TranscriptSession,
        apiKey: String,
        model: String
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
        let body = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                temperature: 0.1,
                responseFormat: .jsonObject,
                messages: [
                    .init(
                        role: "system",
                        content: """
                        You convert spoken software review notes into structured, reviewable draft issues.
                        Use only information explicitly present in the transcript, markers, and screenshot references.
                        Return strict JSON with keys summary, guidanceNote, issues.
                        Each issue must contain title, category, summary, evidenceExcerpt, timestamp, sectionTitle, relatedScreenshotFileNames, confidence, requiresReview.
                        Valid categories are exactly: Bug, UX Issue, Enhancement, Question / Follow-up.
                        Prefer conservative output. If evidence is weak, set requiresReview to true and use a lower confidence.
                        """
                    ),
                    .init(role: "user", content: makePrompt(for: reviewSession))
                ]
            )
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppError.issueExtractionFailure("The server response was invalid.")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                logger.warning(
                    "issue_extraction_request_rejected",
                    "OpenAI rejected the issue extraction request.",
                    metadata: ["status_code": "\(httpResponse.statusCode)"]
                )
                throw OpenAIErrorMapper.mapResponse(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    fallback: AppError.issueExtractionFailure
                )
            }

            let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = completion.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                logger.warning("issue_extraction_empty", "OpenAI returned an empty issue extraction response.")
                throw AppError.issueExtractionFailure("The extraction response was empty.")
            }

            let payload = try JSONDecoder().decode(IssueExtractionPayload.self, from: Data(content.utf8))
            logger.info(
                "issue_extraction_request_succeeded",
                "OpenAI returned extracted review issues.",
                metadata: [
                    "session_id": reviewSession.id.uuidString,
                    "issue_count": "\(payload.issues.count)"
                ]
            )
            return payload.makeIssueExtractionResult(using: reviewSession)
        } catch {
            logger.error(
                "issue_extraction_request_failed",
                (error as? AppError)?.userMessage ?? error.localizedDescription,
                metadata: ["session_id": reviewSession.id.uuidString]
            )
            throw OpenAIErrorMapper.mapTransportError(error, fallback: AppError.issueExtractionFailure)
        }
    }

    private func makePrompt(for session: TranscriptSession) -> String {
        var lines: [String] = [
            "Session metadata:",
            "- Recorded: \(session.createdAt.formatted(date: .abbreviated, time: .standard))",
            "- Duration: \(ElapsedTimeFormatter.string(from: session.duration))",
            "- Transcript model: \(session.model)",
            "",
            "Markers:"
        ]

        if session.markers.isEmpty {
            lines.append("- None")
        } else {
            for marker in session.markers {
                var line = "- \(marker.title) at \(marker.timeLabel)"
                if let note = marker.note, !note.isEmpty {
                    line += " | note: \(note)"
                }
                if let screenshotID = marker.screenshotID,
                   let screenshot = session.screenshot(with: screenshotID) {
                    line += " | screenshot: \(screenshot.fileName)"
                }
                lines.append(line)
            }
        }

        lines.append("")
        lines.append("Screenshots:")
        if session.screenshots.isEmpty {
            lines.append("- None")
        } else {
            for screenshot in session.screenshots {
                var line = "- \(screenshot.fileName) at \(screenshot.timeLabel)"
                if let associatedMarkerID = screenshot.associatedMarkerID,
                   let marker = session.marker(with: associatedMarkerID) {
                    line += " | linked marker: \(marker.title)"
                }
                lines.append(line)
            }
        }

        lines.append("")
        lines.append("Transcript sections:")

        if session.sections.isEmpty {
            lines.append(session.transcript)
        } else {
            for section in session.sections {
                lines.append("## \(section.title) [\(section.timeRangeLabel)]")
                if !section.screenshotIDs.isEmpty {
                    let fileNames = section.screenshotIDs.compactMap { session.screenshot(with: $0)?.fileName }
                    if !fileNames.isEmpty {
                        lines.append("Screenshots: \(fileNames.joined(separator: ", "))")
                    }
                }
                lines.append(section.text)
                lines.append("")
            }
        }

        lines.append("Return a concise summary plus reviewable draft issues for product and engineering triage.")
        return lines.joined(separator: "\n")
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let temperature: Double
    let responseFormat: ResponseFormat
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case responseFormat = "response_format"
        case messages
    }
}

private struct ResponseFormat: Encodable {
    let type: String

    static let jsonObject = ResponseFormat(type: "json_object")
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessageResponse
}

private struct ChatMessageResponse: Decodable {
    let content: String?
}

private struct IssueExtractionPayload: Decodable {
    let summary: String
    let guidanceNote: String?
    let issues: [IssuePayload]

    func makeIssueExtractionResult(using session: TranscriptSession) -> IssueExtractionResult {
        let screenshotIndex = Dictionary(uniqueKeysWithValues: session.screenshots.map { ($0.fileName.lowercased(), $0.id) })
        let issues = issues.map { $0.makeExtractedIssue(screenshotIndex: screenshotIndex) }

        return IssueExtractionResult(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            guidanceNote: guidanceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Extracted issues are draft suggestions and should be reviewed before export.",
            issues: issues
        )
    }
}

private struct IssuePayload: Decodable {
    let title: String
    let category: String
    let summary: String
    let evidenceExcerpt: String
    let timestamp: String?
    let sectionTitle: String?
    let relatedScreenshotFileNames: [String]?
    let confidence: Double?
    let requiresReview: Bool?

    func makeExtractedIssue(screenshotIndex: [String: UUID]) -> ExtractedIssue {
        let screenshotIDs = (relatedScreenshotFileNames ?? []).compactMap { fileName in
            screenshotIndex[fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        }

        return ExtractedIssue(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: parseCategory(category),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceExcerpt: evidenceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: parseTimestamp(timestamp),
            relatedScreenshotIDs: screenshotIDs,
            confidence: confidence,
            requiresReview: requiresReview ?? true,
            isSelectedForExport: true,
            sectionTitle: sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func parseCategory(_ value: String) -> ExtractedIssueCategory {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalizedValue {
        case "bug":
            return .bug
        case "ux issue", "ux", "usability":
            return .uxIssue
        case "enhancement", "enhancement request":
            return .enhancement
        default:
            return .followUp
        }
    }

    private func parseTimestamp(_ value: String?) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }

        let parts = value.split(separator: ":").compactMap { Double($0) }

        switch parts.count {
        case 2:
            return (parts[0] * 60) + parts[1]
        case 3:
            return (parts[0] * 3_600) + (parts[1] * 60) + parts[2]
        default:
            return nil
        }
    }
}
