import Foundation

/// Builds the OpenAI chat-completions request for issue extraction from a
/// `TranscriptSession`: the system/user prompt, the screenshot attachment budget,
/// and the encoded JSON body. This is the no-network "request building" half of
/// the extraction pipeline, split out of `IssueExtractionService` (#432) so the
/// request shape can be unit-tested without touching transport or parsing.
///
/// The output is byte-compatible with the previous in-service implementation; a
/// characterization test pins the encoded request body.
enum IssueExtractionRequestBuilder {
    static func makeRequest(
        endpoint: URL,
        reviewSession: TranscriptSession,
        apiKey: String,
        model: String
    ) throws -> URLRequest {
        let body = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: model,
                temperature: 0.1,
                responseFormat: .jsonObject,
                messages: [
                    .init(
                        role: "system",
                        content: .text("""
                        You convert spoken software review notes into structured, reviewable draft issues.
                        Use only information explicitly present in the transcript, markers, and screenshot references.
                        Return strict JSON with keys summary, guidanceNote, issues.
                        Each issue must contain title, category, severity, component, summary, evidenceExcerpt, deduplicationHint, timestamp, sectionTitle, relatedScreenshotFileNames, confidence, requiresReview, reproductionSteps, screenshotAnnotations.
                        Each reproduction step must contain instruction, expectedResult, actualResult, timestamp, relatedScreenshotFileName.
                        Each screenshot annotation must contain relatedScreenshotFileName, label, x, y, width, height, confidence, style.
                        Generate numbered reproduction steps that follow the narration timeline and tie each step to the most relevant screenshot reference when one exists.
                        When the narration clearly points to a specific UI control or region, return one or more screenshotAnnotations that use normalized 0-1 coordinates relative to the screenshot image.
                        Use a top-left origin for x and y.
                        Only include screenshotAnnotations when the narration or evidence clearly references a specific UI element. Otherwise return an empty array.
                        Valid annotation styles are exactly: highlight.
                        Valid categories are exactly: Bug, UX Issue, Enhancement, Question / Follow-up.
                        Valid severities are exactly: Critical, High, Medium, Low.
                        Infer severity from the narration tone and impact. Infer component from the most specific app area available in the transcript or screenshot context.
                        DeduplicationHint should be a short stable hash-like string derived from the issue description.
                        Prefer conservative output. If evidence is weak, set requiresReview to true and use a lower confidence.
                        """)
                    ),
                    .init(role: "user", content: .parts(makeUserMessageParts(for: reviewSession)))
                ]
            )
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private static func makePrompt(for session: TranscriptSession) -> String {
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

        lines.append(contentsOf: IssueExtractionRequestBudget.transcriptLines(for: session))

        lines.append("Return a concise summary plus reviewable draft issues for product and engineering triage.")
        return lines.joined(separator: "\n")
    }

    private static func makeUserMessageParts(for session: TranscriptSession) -> [ChatMessageInputPart] {
        let logger = DiagnosticsLogger(category: .transcription)
        var parts: [ChatMessageInputPart] = [.text(makePrompt(for: session))]

        var includedScreenshotCount = 0
        var omittedScreenshotCount = 0
        var failedToLoadCount = 0
        var totalScreenshotBytes = 0

        for screenshot in session.screenshots.prefix(IssueExtractionRequestBudget.maximumScreenshotCount) {
            guard let byteCount = IssueExtractionRequestBudget.fileSize(for: screenshot.fileURL),
                  byteCount <= IssueExtractionRequestBudget.maximumSingleScreenshotBytes,
                  totalScreenshotBytes + byteCount <= IssueExtractionRequestBudget.maximumTotalScreenshotBytes else {
                omittedScreenshotCount += 1
                continue
            }

            // Build the image part first: a referenced-but-unattached screenshot
            // would otherwise tell the model an image exists that it never received.
            guard let imagePart = makeScreenshotContentPart(for: screenshot) else {
                failedToLoadCount += 1
                logger.warning(
                    "extraction_screenshot_load_failed",
                    "A referenced screenshot passed the size check but could not be read or encoded for the extraction request.",
                    metadata: ["file_name": screenshot.fileName]
                )
                continue
            }

            parts.append(.text("Screenshot reference: \(screenshot.fileName) at \(screenshot.timeLabel)."))
            parts.append(imagePart)
            includedScreenshotCount += 1
            totalScreenshotBytes += byteCount
        }

        if session.screenshots.count > IssueExtractionRequestBudget.maximumScreenshotCount {
            omittedScreenshotCount += session.screenshots.count - IssueExtractionRequestBudget.maximumScreenshotCount
        }

        if omittedScreenshotCount > 0 {
            parts.append(.text("Screenshot budget note: \(omittedScreenshotCount) screenshot(s) were omitted from AI extraction to keep the request reliable. Use filenames and transcript context for any omitted screenshots."))
        }

        if failedToLoadCount > 0 {
            parts.append(.text("Screenshot attachment note: \(failedToLoadCount) referenced screenshot image(s) failed to attach; do not infer visual details from those filenames."))
        }

        if includedScreenshotCount > 0 {
            parts.append(.text("Screenshot budget note: included \(includedScreenshotCount) screenshot(s), \(totalScreenshotBytes) total bytes."))
        }

        return parts
    }

    private static func makeScreenshotContentPart(for screenshot: SessionScreenshot) -> ChatMessageInputPart? {
        guard let imageData = try? Data(contentsOf: screenshot.fileURL),
              let mimeType = mimeType(for: screenshot.fileURL) else {
            return nil
        }

        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        return .imageURL(dataURL)
    }

    private static func mimeType(for fileURL: URL) -> String? {
        switch fileURL.pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "heic":
            return "image/heic"
        case "webp":
            return "image/webp"
        default:
            return nil
        }
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

enum IssueExtractionRequestBudget {
    static let maximumTranscriptCharacters = 24_000
    static let maximumScreenshotCount = 4
    static let maximumSingleScreenshotBytes = 2 * 1_024 * 1_024
    static let maximumTotalScreenshotBytes = 6 * 1_024 * 1_024

    static func transcriptLines(for session: TranscriptSession) -> [String] {
        var remainingCharacters = maximumTranscriptCharacters
        var lines: [String] = []
        var omittedCharacterCount = 0

        func appendBudgetedText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }

            if trimmed.count <= remainingCharacters {
                lines.append(trimmed)
                remainingCharacters -= trimmed.count
                return
            }

            if remainingCharacters > 0 {
                let endIndex = trimmed.index(trimmed.startIndex, offsetBy: remainingCharacters)
                lines.append(String(trimmed[..<endIndex]))
            }
            omittedCharacterCount += trimmed.count - max(remainingCharacters, 0)
            remainingCharacters = 0
        }

        if session.sections.isEmpty {
            appendBudgetedText(session.transcript)
        } else {
            for section in session.sections {
                guard remainingCharacters > 0 else {
                    omittedCharacterCount += section.text.count
                    continue
                }

                lines.append("## \(section.title) [\(section.timeRangeLabel)]")
                if !section.screenshotIDs.isEmpty {
                    let fileNames = section.screenshotIDs.compactMap { session.screenshot(with: $0)?.fileName }
                    if !fileNames.isEmpty {
                        lines.append("Screenshots: \(fileNames.joined(separator: ", "))")
                    }
                }
                appendBudgetedText(section.text)
                lines.append("")
            }
        }

        if omittedCharacterCount > 0 {
            lines.append("[Budget note: omitted \(omittedCharacterCount) transcript character(s) from the extraction request. Export or inspect the full transcript locally if needed.]")
        }

        return lines
    }

    static func fileSize(for url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return (attributes[.size] as? NSNumber)?.intValue
    }
}

private struct ResponseFormat: Encodable {
    let type: String

    static let jsonObject = ResponseFormat(type: "json_object")
}

private struct ChatMessage: Encodable {
    let role: String
    let content: ChatMessageContent
}

private enum ChatMessageContent: Encodable {
    case text(String)
    case parts([ChatMessageInputPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .text(let value):
            try container.encode(value)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

private enum ChatMessageInputPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let value):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: value), forKey: .imageURL)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ImageURLPayload: Encodable {
    let url: String
}
