import Foundation

actor IssueExtractionService: IssueExtracting {
    static let defaultTimeoutDuration: Duration = .seconds(10)

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
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
        do {
            let request = try Self.makeRequest(
                endpoint: endpoint,
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

    private static func makeRequest(
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private static func makeUserMessageParts(for session: TranscriptSession) -> [ChatMessageInputPart] {
        var parts: [ChatMessageInputPart] = [.text(makePrompt(for: session))]

        var includedScreenshotCount = 0
        var omittedScreenshotCount = 0
        var totalScreenshotBytes = 0

        for screenshot in session.screenshots.prefix(IssueExtractionRequestBudget.maximumScreenshotCount) {
            guard let byteCount = IssueExtractionRequestBudget.fileSize(for: screenshot.fileURL),
                  byteCount <= IssueExtractionRequestBudget.maximumSingleScreenshotBytes,
                  totalScreenshotBytes + byteCount <= IssueExtractionRequestBudget.maximumTotalScreenshotBytes else {
                omittedScreenshotCount += 1
                continue
            }

            parts.append(.text("Screenshot reference: \(screenshot.fileName) at \(screenshot.timeLabel)."))

            guard let imagePart = makeScreenshotContentPart(for: screenshot) else {
                omittedScreenshotCount += 1
                continue
            }

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

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let message = completion.choices.first?.message else {
            throw AppError.issueExtractionFailure("The extraction response was empty.")
        }

        if let refusal = message.refusal?.trimmingCharacters(in: .whitespacesAndNewlines),
           !refusal.isEmpty {
            throw AppError.issueExtractionFailure(refusal)
        }

        guard let content = message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            throw AppError.issueExtractionFailure("The extraction response was empty.")
        }

        do {
            let payload = try IssueExtractionPayload.parse(from: content)
            return payload.makeIssueExtractionResult(using: reviewSession)
        } catch {
            throw AppError.issueExtractionFailure(
                "OpenAI returned issue data in an unexpected format. Try again, or switch the issue extraction model in Settings."
            )
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

private enum IssueExtractionRequestBudget {
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

private struct ChatCompletionResponse: Decodable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Decodable {
    let message: ChatMessageResponse
}

private struct ChatMessageResponse: Decodable {
    let content: String?
    let refusal: String?

    enum CodingKeys: String, CodingKey {
        case content
        case refusal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refusal = try? container.decodeIfPresent(String.self, forKey: .refusal)

        if let content = try? container.decodeIfPresent(String.self, forKey: .content) {
            self.content = content
            return
        }

        if let parts = try? container.decodeIfPresent([ChatMessageContentPart].self, forKey: .content) {
            let joinedContent = parts
                .compactMap(\.text)
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.content = joinedContent.isEmpty ? nil : joinedContent
            return
        }

        content = nil
    }
}

private struct ChatMessageContentPart: Decodable {
    let text: String?
}

private struct IssueExtractionPayload {
    let summary: String
    let guidanceNote: String?
    let issues: [IssuePayload]

    static func parse(from content: String) throws -> IssueExtractionPayload {
        var parseErrors: [String] = []

        for candidate in jsonCandidates(from: content) {
            do {
                return try parse(from: candidate)
            } catch {
                parseErrors.append(String(describing: error))
            }
        }

        throw IssueExtractionParseError.invalidPayload(parseErrors.joined(separator: " | "))
    }

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

    private static func parse(from data: Data) throws -> IssueExtractionPayload {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = jsonObject as? [String: Any] else {
            throw IssueExtractionParseError.invalidPayload("Top-level issue extraction payload was not a JSON object.")
        }

        let summary = firstString(in: dictionary, keys: ["summary", "reviewSummary", "review_summary"])?.trimmedForExtraction
        let guidanceNote = firstString(in: dictionary, keys: ["guidanceNote", "guidance_note", "reviewGuidance", "review_guidance"])?.trimmedForExtraction
        let issueObjects = firstArray(in: dictionary, keys: ["issues", "draftIssues", "draft_issues", "items"]) ?? []

        let issues = issueObjects.compactMap { issueObject -> IssuePayload? in
            guard let issueDictionary = issueObject as? [String: Any] else {
                return nil
            }

            return IssuePayload(dictionary: issueDictionary)
        }

        if summary == nil, guidanceNote == nil, issues.isEmpty {
            throw IssueExtractionParseError.invalidPayload("Issue extraction payload did not contain a summary, guidance note, or issues.")
        }

        if !issueObjects.isEmpty, issues.isEmpty {
            throw IssueExtractionParseError.invalidPayload("Issue extraction payload contained issues, but none matched the expected structure.")
        }

        return IssueExtractionPayload(
            summary: summary ?? "",
            guidanceNote: guidanceNote,
            issues: issues
        )
    }

    private static func jsonCandidates(from content: String) -> [Data] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        var seen = Set<String>()

        func appendCandidate(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                return
            }
            candidates.append(normalized)
        }

        appendCandidate(trimmed)

        if let unfenced = stripMarkdownFence(from: trimmed) {
            appendCandidate(unfenced)
        }

        if let extractedJSONObject = extractJSONObjectString(from: trimmed) {
            appendCandidate(extractedJSONObject)
        }

        return candidates.map { Data($0.utf8) }
    }

    private static func stripMarkdownFence(from content: String) -> String? {
        guard content.hasPrefix("```") else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.count >= 3 else {
            return nil
        }

        let closingFenceIndex = lines.lastIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines) == "```" }
        guard let closingFenceIndex, closingFenceIndex > lines.startIndex else {
            return nil
        }

        let bodyLines = lines[(lines.startIndex + 1)..<closingFenceIndex]
        return bodyLines.joined(separator: "\n")
    }

    private static func extractJSONObjectString(from content: String) -> String? {
        guard let startIndex = content.firstIndex(of: "{"),
              let endIndex = content.lastIndex(of: "}") else {
            return nil
        }

        return String(content[startIndex...endIndex])
    }

    fileprivate static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }

        return nil
    }

    private static func firstArray(in dictionary: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let value = dictionary[key] as? [Any] {
                return value
            }
        }

        return nil
    }
}

private struct IssuePayload {
    private static let criticalSeveritySignals = [
        "crash",
        "crashes",
        "data loss",
        "completely broken",
        "blocked",
        "blocker",
        "cannot continue",
        "can't continue",
        "unable to continue",
        "won't open",
        "blank screen"
    ]

    private static let lowSeveritySignals = [
        "minor",
        "small",
        "cosmetic",
        "visual glitch",
        "visual issue",
        "spacing",
        "alignment",
        "typo",
        "copy issue"
    ]

    private static let highSeveritySignals = [
        "broken",
        "doesn't work",
        "does not work",
        "not respond",
        "fails",
        "failure",
        "unable to",
        "cannot",
        "can't",
        "stuck"
    ]

    let title: String
    let category: String
    let severity: String?
    let component: String?
    let summary: String
    let evidenceExcerpt: String
    let deduplicationHint: String?
    let timestamp: String?
    let sectionTitle: String?
    let relatedScreenshotFileNames: [String]?
    let confidence: Double?
    let requiresReview: Bool?
    let reproductionSteps: [IssueReproductionStepPayload]
    let screenshotAnnotations: [IssueScreenshotAnnotationPayload]

    init?(dictionary: [String: Any]) {
        let title = Self.firstString(in: dictionary, keys: ["title", "issueTitle", "name"])?.trimmedForExtraction
        let category = Self.firstString(in: dictionary, keys: ["category", "type", "classification"])?.trimmedForExtraction
        let summary = Self.firstString(in: dictionary, keys: ["summary", "description", "details"])?.trimmedForExtraction
        let evidenceExcerpt = Self.firstString(in: dictionary, keys: ["evidenceExcerpt", "evidence", "evidenceQuote", "evidence_excerpt"])?.trimmedForExtraction

        guard let title, !title.isEmpty,
              let category, !category.isEmpty,
              let summary, !summary.isEmpty,
              let evidenceExcerpt, !evidenceExcerpt.isEmpty else {
            return nil
        }

        self.title = title
        self.category = category
        self.severity = Self.firstString(
            in: dictionary,
            keys: ["severity", "priority", "impact"]
        )?.trimmedForExtraction
        self.component = Self.firstString(
            in: dictionary,
            keys: ["component", "area", "affectedComponent", "affected_component", "surface", "scope"]
        )?.trimmedForExtraction
        self.summary = summary
        self.evidenceExcerpt = evidenceExcerpt
        self.deduplicationHint = Self.firstString(
            in: dictionary,
            keys: ["deduplicationHint", "dedupHint", "dedup_hint", "duplicateHint", "duplicate_hint"]
        )?.trimmedForExtraction
        self.timestamp = Self.firstString(in: dictionary, keys: ["timestamp", "time", "timecode"])?.trimmedForExtraction
        self.sectionTitle = Self.firstString(in: dictionary, keys: ["sectionTitle", "section", "sectionName"])?.trimmedForExtraction
        self.relatedScreenshotFileNames = Self.firstStringArray(
            in: dictionary,
            keys: ["relatedScreenshotFileNames", "screenshotFileNames", "screenshots", "related_screenshot_file_names"]
        )
        self.confidence = Self.firstDouble(in: dictionary, keys: ["confidence", "score"])
        self.requiresReview = Self.firstBool(in: dictionary, keys: ["requiresReview", "requires_review", "needsReview"])
        self.reproductionSteps = Self.firstArray(
            in: dictionary,
            keys: ["reproductionSteps", "stepsToReproduce", "steps_to_reproduce", "reproSteps", "steps"]
        )?.compactMap { stepObject in
            guard let stepDictionary = stepObject as? [String: Any] else {
                return nil
            }

            return IssueReproductionStepPayload(dictionary: stepDictionary)
        } ?? []
        self.screenshotAnnotations = Self.firstArray(
            in: dictionary,
            keys: ["screenshotAnnotations", "annotations", "screenshot_annotations", "uiAnnotations"]
        )?.compactMap { annotationObject in
            guard let annotationDictionary = annotationObject as? [String: Any] else {
                return nil
            }

            return IssueScreenshotAnnotationPayload(dictionary: annotationDictionary)
        } ?? []
    }

    func makeExtractedIssue(screenshotIndex: [String: UUID]) -> ExtractedIssue {
        let screenshotIDs = (relatedScreenshotFileNames ?? []).compactMap { fileName in
            screenshotIndex[fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        }
        let parsedTimestamp = Self.parseTimestamp(timestamp)
        let reproductionSteps = reproductionSteps.map {
            $0.makeIssueReproductionStep(
                screenshotIndex: screenshotIndex,
                fallbackTimestamp: parsedTimestamp,
                fallbackScreenshotID: screenshotIDs.first
            )
        }
        let annotations = screenshotAnnotations.compactMap {
            $0.makeIssueScreenshotAnnotation(
                screenshotIndex: screenshotIndex,
                fallbackScreenshotID: screenshotIDs.first
            )
        }

        return ExtractedIssue(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: Self.parseCategory(category),
            severity: Self.parseSeverity(severity, title: title, summary: summary, evidenceExcerpt: evidenceExcerpt),
            component: normalizedComponent,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceExcerpt: evidenceExcerpt.trimmingCharacters(in: .whitespacesAndNewlines),
            deduplicationHint: deduplicationHint?.trimmingCharacters(in: .whitespacesAndNewlines),
            timestamp: parsedTimestamp,
            relatedScreenshotIDs: screenshotIDs,
            confidence: confidence,
            requiresReview: requiresReview ?? true,
            isSelectedForExport: true,
            sectionTitle: sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            reproductionSteps: reproductionSteps,
            screenshotAnnotations: annotations
        )
    }

    private var normalizedComponent: String? {
        if let component = component?.trimmingCharacters(in: .whitespacesAndNewlines),
           !component.isEmpty {
            return component
        }

        if let sectionTitle = sectionTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sectionTitle.isEmpty {
            return sectionTitle
        }

        return nil
    }

    fileprivate static func firstString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                return value
            }
        }

        return nil
    }

    fileprivate static func firstArray(in dictionary: [String: Any], keys: [String]) -> [Any]? {
        for key in keys {
            if let value = dictionary[key] as? [Any] {
                return value
            }
        }

        return nil
    }

    fileprivate static func firstStringArray(in dictionary: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let values = dictionary[key] as? [String] {
                return values
            }

            if let values = dictionary[key] as? [Any] {
                let strings = values.compactMap { $0 as? String }
                if !strings.isEmpty {
                    return strings
                }
            }
        }

        return nil
    }

    private static func firstDouble(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double {
                return value
            }

            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }

            if let value = dictionary[key] as? String, let doubleValue = Double(value) {
                return doubleValue
            }
        }

        return nil
    }

    private static func firstBool(in dictionary: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dictionary[key] as? Bool {
                return value
            }
        }

        return nil
    }

    fileprivate static func parseCategory(_ value: String) -> ExtractedIssueCategory {
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

    fileprivate static func parseSeverity(
        _ value: String?,
        title: String,
        summary: String,
        evidenceExcerpt: String
    ) -> ExtractedIssueSeverity {
        if let value {
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            switch normalizedValue {
            case "critical", "blocker", "sev1", "p0":
                return .critical
            case "high", "major", "sev2", "p1":
                return .high
            case "medium", "moderate", "normal", "sev3", "p2":
                return .medium
            case "low", "minor", "cosmetic", "sev4", "p3":
                return .low
            default:
                break
            }
        }

        let combinedText = [
            title,
            summary,
            evidenceExcerpt
        ]
        .joined(separator: " ")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .lowercased()

        if Self.criticalSeveritySignals.contains(where: combinedText.contains) {
            return .critical
        }

        if Self.lowSeveritySignals.contains(where: combinedText.contains) {
            return .low
        }

        if Self.highSeveritySignals.contains(where: combinedText.contains) {
            return .high
        }

        return .medium
    }

    fileprivate static func parseTimestamp(_ value: String?) -> TimeInterval? {
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

private struct IssueReproductionStepPayload {
    let instruction: String
    let expectedResult: String?
    let actualResult: String?
    let timestamp: String?
    let relatedScreenshotFileName: String?

    init?(dictionary: [String: Any]) {
        let instruction = IssuePayload.firstString(
            in: dictionary,
            keys: ["instruction", "step", "action", "description"]
        )?.trimmedForExtraction

        guard let instruction, !instruction.isEmpty else {
            return nil
        }

        self.instruction = instruction
        self.expectedResult = IssuePayload.firstString(
            in: dictionary,
            keys: ["expectedResult", "expected", "expected_result"]
        )?.trimmedForExtraction.nilIfEmpty
        self.actualResult = IssuePayload.firstString(
            in: dictionary,
            keys: ["actualResult", "actual", "actual_result"]
        )?.trimmedForExtraction.nilIfEmpty
        self.timestamp = IssuePayload.firstString(
            in: dictionary,
            keys: ["timestamp", "time", "timecode"]
        )?.trimmedForExtraction
        self.relatedScreenshotFileName =
            IssuePayload.firstString(
                in: dictionary,
                keys: ["relatedScreenshotFileName", "screenshotFileName", "screenshot", "related_screenshot_file_name"]
            )?.trimmedForExtraction ??
            IssuePayload.firstStringArray(
                in: dictionary,
                keys: ["relatedScreenshotFileNames", "screenshotFileNames", "screenshots"]
            )?.first?.trimmedForExtraction
    }

    func makeIssueReproductionStep(
        screenshotIndex: [String: UUID],
        fallbackTimestamp: TimeInterval?,
        fallbackScreenshotID: UUID?
    ) -> IssueReproductionStep {
        let screenshotID = relatedScreenshotFileName.flatMap {
            screenshotIndex[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        } ?? fallbackScreenshotID

        return IssueReproductionStep(
            instruction: instruction,
            expectedResult: expectedResult,
            actualResult: actualResult,
            timestamp: IssuePayload.parseTimestamp(timestamp) ?? fallbackTimestamp,
            screenshotID: screenshotID
        )
    }
}

private struct IssueScreenshotAnnotationPayload {
    private static let xKeys = ["x", "left", "originX", "origin_x", "minX"]
    private static let yKeys = ["y", "top", "originY", "origin_y", "minY"]
    private static let widthKeys = ["width", "w"]
    private static let heightKeys = ["height", "h"]

    let relatedScreenshotFileName: String?
    let label: String?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let confidence: Double?
    let style: String?

    init?(dictionary: [String: Any]) {
        guard let x = Self.firstDouble(in: dictionary, keys: Self.xKeys),
              let y = Self.firstDouble(in: dictionary, keys: Self.yKeys),
              let width = Self.firstDouble(in: dictionary, keys: Self.widthKeys),
              let height = Self.firstDouble(in: dictionary, keys: Self.heightKeys) else {
            return nil
        }

        self.relatedScreenshotFileName = IssuePayload.firstString(
            in: dictionary,
            keys: ["relatedScreenshotFileName", "screenshot", "screenshotFileName", "fileName", "related_screenshot_file_name"]
        )?.trimmedForExtraction
        self.label = IssuePayload.firstString(
            in: dictionary,
            keys: ["label", "title", "target", "description"]
        )?.trimmedForExtraction.nilIfEmpty
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.confidence = Self.firstDouble(in: dictionary, keys: ["confidence", "score"])
        self.style = IssuePayload.firstString(in: dictionary, keys: ["style", "kind"])?.trimmedForExtraction
    }

    func makeIssueScreenshotAnnotation(
        screenshotIndex: [String: UUID],
        fallbackScreenshotID: UUID?
    ) -> IssueScreenshotAnnotation? {
        let screenshotID = relatedScreenshotFileName.flatMap {
            screenshotIndex[$0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        } ?? fallbackScreenshotID

        guard let screenshotID else {
            return nil
        }

        let annotationStyle: IssueScreenshotAnnotation.Style
        switch style?.lowercased() {
        case nil, "", "highlight", "box", "outline":
            annotationStyle = .highlight
        default:
            annotationStyle = .highlight
        }

        return IssueScreenshotAnnotation(
            screenshotID: screenshotID,
            label: label,
            x: x,
            y: y,
            width: width,
            height: height,
            confidence: confidence,
            style: annotationStyle
        )
    }

    private static func firstDouble(in dictionary: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dictionary[key] as? Double {
                return value
            }

            if let value = dictionary[key] as? NSNumber {
                return value.doubleValue
            }

            if let value = dictionary[key] as? String, let doubleValue = Double(value) {
                return doubleValue
            }
        }

        return nil
    }
}

private enum IssueExtractionParseError: Error {
    case invalidPayload(String)
}

private extension String {
    var trimmedForExtraction: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
