import Foundation

struct TranscriptSession: SessionLibraryItem, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let transcript: String
    let duration: TimeInterval
    let model: String
    let languageHint: String?
    let prompt: String?
    let markers: [SessionMarker]
    let screenshots: [SessionScreenshot]
    let sections: [TranscriptSection]
    var issueExtraction: IssueExtractionResult?
    let artifactsDirectoryPath: String?

    init(
        id: UUID = UUID(),
        createdAt: Date,
        transcript: String,
        duration: TimeInterval,
        model: String,
        languageHint: String?,
        prompt: String?,
        markers: [SessionMarker] = [],
        screenshots: [SessionScreenshot] = [],
        sections: [TranscriptSection] = [],
        issueExtraction: IssueExtractionResult? = nil,
        updatedAt: Date? = nil,
        artifactsDirectoryPath: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.transcript = transcript
        self.duration = duration
        self.model = model
        self.languageHint = languageHint
        self.prompt = prompt
        self.markers = markers
        self.screenshots = screenshots
        self.sections = sections
        self.issueExtraction = issueExtraction
        self.artifactsDirectoryPath = artifactsDirectoryPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.createdAt = createdAt
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        self.transcript = try container.decode(String.self, forKey: .transcript)
        self.duration = try container.decode(TimeInterval.self, forKey: .duration)
        self.model = try container.decode(String.self, forKey: .model)
        self.languageHint = try container.decodeIfPresent(String.self, forKey: .languageHint)
        self.prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        self.markers = try container.decodeIfPresent([SessionMarker].self, forKey: .markers) ?? []
        self.screenshots = try container.decodeIfPresent([SessionScreenshot].self, forKey: .screenshots) ?? []
        self.sections = try container.decodeIfPresent([TranscriptSection].self, forKey: .sections) ?? []
        self.issueExtraction = try container.decodeIfPresent(IssueExtractionResult.self, forKey: .issueExtraction)
        self.artifactsDirectoryPath = try container.decodeIfPresent(String.self, forKey: .artifactsDirectoryPath)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(transcript, forKey: .transcript)
        try container.encode(duration, forKey: .duration)
        try container.encode(model, forKey: .model)
        try container.encodeIfPresent(languageHint, forKey: .languageHint)
        try container.encodeIfPresent(prompt, forKey: .prompt)
        try container.encode(markers, forKey: .markers)
        try container.encode(screenshots, forKey: .screenshots)
        try container.encode(sections, forKey: .sections)
        try container.encodeIfPresent(issueExtraction, forKey: .issueExtraction)
        try container.encodeIfPresent(artifactsDirectoryPath, forKey: .artifactsDirectoryPath)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case updatedAt
        case transcript
        case duration
        case model
        case languageHint
        case prompt
        case markers
        case screenshots
        case sections
        case issueExtraction
        case artifactsDirectoryPath
    }

    var title: String {
        Self.displayTitle(from: transcript)
    }

    var preview: String {
        Self.previewText(from: transcript)
    }

    var metadataSummary: String {
        let formattedDate = createdAt.formatted(date: .abbreviated, time: .shortened)
        return "\(formattedDate)  •  \(ElapsedTimeFormatter.string(from: duration))  •  \(model)"
    }

    var markerCount: Int {
        markers.count
    }

    var screenshotCount: Int {
        screenshots.count
    }

    var issueCount: Int {
        issueExtraction?.issues.count ?? 0
    }

    var summaryText: String {
        issueExtraction?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var searchIndexText: String {
        Self.makeSearchIndexText(
            transcript: transcript,
            summaryText: summaryText,
            markers: markers,
            issues: issueExtraction?.issues ?? []
        )
    }

    var artifactsDirectoryURL: URL? {
        guard let artifactsDirectoryPath, !artifactsDirectoryPath.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: artifactsDirectoryPath, isDirectory: true)
    }

    func suggestedFileName(fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "bugnarrator-session-\(formatter.string(from: createdAt)).\(fileExtension)"
    }

    var suggestedBundleDirectoryName: String {
        suggestedFileName(fileExtension: "session")
    }

    func screenshot(with id: UUID) -> SessionScreenshot? {
        screenshots.first { $0.id == id }
    }

    func marker(with id: UUID) -> SessionMarker? {
        markers.first { $0.id == id }
    }

    func screenshots(for issue: ExtractedIssue) -> [SessionScreenshot] {
        issue.relatedScreenshotIDs.compactMap(screenshot(with:))
    }

    var plainTextContent: String {
        var lines = [
            "BugNarrator Transcript",
            "Recorded: \(createdAt.formatted(date: .abbreviated, time: .standard))",
            "Duration: \(ElapsedTimeFormatter.string(from: duration))",
            "Model: \(model)"
        ]

        if let languageHint, !languageHint.isEmpty {
            lines.append("Language Hint: \(languageHint)")
        }

        if let prompt, !prompt.isEmpty {
            lines.append("Prompt: \(prompt)")
        }

        if !markers.isEmpty {
            lines.append("Markers:")
            for marker in markers {
                var markerLine = "- \(marker.title) (\(marker.timeLabel))"
                if let note = marker.note, !note.isEmpty {
                    markerLine += " — \(note)"
                }
                lines.append(markerLine)
            }
        }

        if !screenshots.isEmpty {
            lines.append("Screenshots:")
            for screenshot in screenshots {
                var screenshotLine = "- \(screenshot.fileName) (\(screenshot.timeLabel))"
                if let associatedMarkerID = screenshot.associatedMarkerID,
                   let marker = marker(with: associatedMarkerID) {
                    screenshotLine += " linked to \(marker.title)"
                }
                lines.append(screenshotLine)
            }
        }

        if !sections.isEmpty {
            lines.append("")
            lines.append("Transcript Sections:")
            for section in sections {
                lines.append("")
                lines.append("[\(section.timeRangeLabel)] \(section.title)")
                lines.append(section.text)
            }
        }

        lines.append("")
        lines.append("Raw Transcript")
        lines.append(transcript)

        return lines.joined(separator: "\n")
    }

    var markdownContent: String {
        var lines = [
            "# BugNarrator Transcript",
            "",
            "- Recorded: \(createdAt.formatted(date: .abbreviated, time: .standard))",
            "- Duration: \(ElapsedTimeFormatter.string(from: duration))",
            "- Model: \(model)"
        ]

        if let languageHint, !languageHint.isEmpty {
            lines.append("- Language Hint: \(languageHint)")
        }

        if let prompt, !prompt.isEmpty {
            lines.append("- Prompt: \(prompt)")
        }

        lines.append("")
        if !markers.isEmpty {
            lines.append("## Markers")
            lines.append("")
            for marker in markers {
                var markerLine = "- **\(marker.title)** at `\(marker.timeLabel)`"
                if let note = marker.note, !note.isEmpty {
                    markerLine += " — \(note)"
                }
                lines.append(markerLine)
            }
            lines.append("")
        }

        if !screenshots.isEmpty {
            lines.append("## Screenshots")
            lines.append("")
            for screenshot in screenshots {
                var screenshotLine = "- **\(screenshot.fileName)** at `\(screenshot.timeLabel)`"
                if let associatedMarkerID = screenshot.associatedMarkerID,
                   let marker = marker(with: associatedMarkerID) {
                    screenshotLine += " linked to **\(marker.title)**"
                }
                lines.append(screenshotLine)
            }
            lines.append("")
        }

        if !sections.isEmpty {
            lines.append("## Transcript Sections")
            lines.append("")
            for section in sections {
                lines.append("### \(section.title)")
                lines.append("")
                lines.append("- Time: \(section.timeRangeLabel)")
                lines.append("")
                lines.append(section.text)
                lines.append("")
            }
        }

        lines.append("## Raw Transcript")
        lines.append("")
        lines.append(transcript)

        return lines.joined(separator: "\n")
    }

    var summaryMarkdownContent: String {
        var lines = [
            "# BugNarrator Review Output",
            "",
            "- Recorded: \(createdAt.formatted(date: .abbreviated, time: .standard))",
            "- Duration: \(ElapsedTimeFormatter.string(from: duration))",
            "- Transcript Model: \(model)"
        ]

        guard let issueExtraction else {
            lines.append("")
            lines.append("Issue extraction has not been run for this session yet.")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("## Summary")
        lines.append("")
        lines.append(issueExtraction.summary.isEmpty ? "No summary generated." : issueExtraction.summary)
        lines.append("")
        lines.append("> \(issueExtraction.guidanceNote)")
        lines.append("")

        for category in ExtractedIssueCategory.allCases {
            let items = issueExtraction.issues.filter { $0.category == category }
            lines.append(contentsOf: markdownLines(title: category.rawValue, items: items))
        }

        return lines.joined(separator: "\n")
    }

    private func markdownLines(title: String, items: [ExtractedIssue]) -> [String] {
        var lines = ["## \(title)", ""]

        guard !items.isEmpty else {
            lines.append("None identified.")
            lines.append("")
            return lines
        }

        for item in items {
            lines.append("- **\(item.title)**: \(item.summary)")

            var contextParts: [String] = []
            if let sectionTitle = item.sectionTitle, !sectionTitle.isEmpty {
                contextParts.append(sectionTitle)
            }
            if let timestampLabel = item.timestampLabel {
                contextParts.append(timestampLabel)
            }
            if let confidenceLabel = item.confidenceLabel {
                contextParts.append("confidence \(confidenceLabel)")
            }
            if item.requiresReview {
                contextParts.append("review needed")
            }

            if !contextParts.isEmpty {
                lines.append("  Context: \(contextParts.joined(separator: "  •  "))")
            }
            lines.append("  Evidence: \(item.evidenceExcerpt)")

            let relatedScreenshots = screenshots(for: item)
            if !relatedScreenshots.isEmpty {
                let fileNames = relatedScreenshots.map(\.fileName).joined(separator: ", ")
                lines.append("  Screenshots: \(fileNames)")
            }
        }

        lines.append("")
        return lines
    }

    static func displayTitle(from transcript: String) -> String {
        let normalized = normalizedTranscriptBody(from: transcript)

        guard !normalized.isEmpty else {
            return "Untitled Session"
        }

        return truncatedSnippet(from: normalized, limit: 72)
    }

    static func previewText(from transcript: String) -> String {
        let normalized = normalizedTranscriptBody(from: transcript)
        guard !normalized.isEmpty else {
            return "Transcript preview will appear here after the session is transcribed."
        }

        return truncatedSnippet(from: normalized, limit: 160)
    }

    static func makeSearchIndexText(
        transcript: String,
        summaryText: String,
        markers: [SessionMarker],
        issues: [ExtractedIssue]
    ) -> String {
        let title = displayTitle(from: transcript)
        let preview = previewText(from: transcript)

        return [
            title,
            preview,
            transcript,
            summaryText,
            markers.map(\.title).joined(separator: " "),
            markers.compactMap(\.note).joined(separator: " "),
            issues.map(\.title).joined(separator: " "),
            issues.map(\.summary).joined(separator: " ")
        ]
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func normalizedTranscriptBody(from transcript: String) -> String {
        transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncatedSnippet(from text: String, limit: Int) -> String {
        guard text.count > limit else {
            return text
        }

        let prefix = String(text.prefix(limit))
        if let boundary = prefix.lastIndex(where: \.isWhitespace),
           boundary > prefix.startIndex {
            return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }

        return prefix.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
