import Foundation

/// Parses a successful OpenAI chat-completions response into an
/// `IssueExtractionResult`: response-envelope decoding, schema-repair / alias
/// mapping of the model's JSON, and normalization of issues, reproduction steps,
/// and screenshot annotations. This is the no-network "response parsing + issue
/// normalization" half of the extraction pipeline, split out of
/// `IssueExtractionService` (#519) so it can be unit-tested without transport.
///
/// Behavior is byte-compatible with the previous in-service implementation,
/// including the exact failure messages for empty / refusal / unparseable
/// responses.
enum IssueExtractionResponseParser {
    /// Decodes a successful (2xx) chat-completions HTTP body into an extraction
    /// result. Throws `AppError.issueExtractionFailure` with the same messages the
    /// service previously produced for empty, refusal, or unparseable content. A
    /// failure to decode the response envelope itself propagates unmapped (the
    /// caller maps transport-level errors), matching the prior behavior.
    static func parseResult(from data: Data, session: TranscriptSession) throws -> IssueExtractionResult {
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
            return payload.makeIssueExtractionResult(using: session)
        } catch {
            throw AppError.issueExtractionFailure(
                "OpenAI returned issue data in an unexpected format. Try again, or switch the issue extraction model in Settings."
            )
        }
    }
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
