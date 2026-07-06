import Foundation

struct ExtractedIssue: Identifiable, Codable, Equatable {
    private static let deduplicationNormalizationLocale = Locale(identifier: "en_US_POSIX")

    let id: UUID
    var title: String
    var category: ExtractedIssueCategory
    var severity: ExtractedIssueSeverity
    var component: String?
    var summary: String
    var evidenceExcerpt: String
    var deduplicationHint: String
    var timestamp: TimeInterval?
    var relatedScreenshotIDs: [UUID]
    var confidence: Double?
    var requiresReview: Bool
    var isSelectedForExport: Bool
    var sectionTitle: String?
    var reproductionSteps: [IssueReproductionStep]
    var screenshotAnnotations: [IssueScreenshotAnnotation]
    var note: String?
    var gitHubExportTarget: GitHubIssueExportTarget?
    var jiraExportTarget: JiraIssueExportTarget?

    init(
        id: UUID = UUID(),
        title: String,
        category: ExtractedIssueCategory,
        severity: ExtractedIssueSeverity = .medium,
        component: String? = nil,
        summary: String,
        evidenceExcerpt: String,
        deduplicationHint: String? = nil,
        timestamp: TimeInterval?,
        relatedScreenshotIDs: [UUID] = [],
        confidence: Double? = nil,
        requiresReview: Bool = true,
        isSelectedForExport: Bool = true,
        sectionTitle: String? = nil,
        reproductionSteps: [IssueReproductionStep] = [],
        screenshotAnnotations: [IssueScreenshotAnnotation] = [],
        note: String? = nil,
        gitHubExportTarget: GitHubIssueExportTarget? = nil,
        jiraExportTarget: JiraIssueExportTarget? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.severity = severity
        self.component = component?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.summary = summary
        self.evidenceExcerpt = evidenceExcerpt
        self.deduplicationHint = Self.normalizedDeduplicationHint(
            deduplicationHint,
            title: title,
            summary: summary,
            evidenceExcerpt: evidenceExcerpt
        )
        self.timestamp = timestamp
        self.relatedScreenshotIDs = relatedScreenshotIDs
        self.confidence = confidence
        self.requiresReview = requiresReview
        self.isSelectedForExport = isSelectedForExport
        self.sectionTitle = sectionTitle
        self.reproductionSteps = reproductionSteps
        self.screenshotAnnotations = screenshotAnnotations
        self.note = note
        self.gitHubExportTarget = gitHubExportTarget
        self.jiraExportTarget = jiraExportTarget
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(ExtractedIssueCategory.self, forKey: .category)
        severity = try container.decodeIfPresent(ExtractedIssueSeverity.self, forKey: .severity) ?? .medium
        component = try container.decodeIfPresent(String.self, forKey: .component)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        summary = try container.decode(String.self, forKey: .summary)
        evidenceExcerpt = try container.decode(String.self, forKey: .evidenceExcerpt)
        deduplicationHint = Self.normalizedDeduplicationHint(
            try container.decodeIfPresent(String.self, forKey: .deduplicationHint),
            title: title,
            summary: summary,
            evidenceExcerpt: evidenceExcerpt
        )
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
        relatedScreenshotIDs = try container.decodeIfPresent([UUID].self, forKey: .relatedScreenshotIDs) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        requiresReview = try container.decodeIfPresent(Bool.self, forKey: .requiresReview) ?? true
        isSelectedForExport = try container.decodeIfPresent(Bool.self, forKey: .isSelectedForExport) ?? true
        sectionTitle = try container.decodeIfPresent(String.self, forKey: .sectionTitle)
        reproductionSteps = try container.decodeIfPresent([IssueReproductionStep].self, forKey: .reproductionSteps) ?? []
        screenshotAnnotations = try container.decodeIfPresent([IssueScreenshotAnnotation].self, forKey: .screenshotAnnotations) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        gitHubExportTarget = try container.decodeIfPresent(GitHubIssueExportTarget.self, forKey: .gitHubExportTarget)
        jiraExportTarget = try container.decodeIfPresent(JiraIssueExportTarget.self, forKey: .jiraExportTarget)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(component, forKey: .component)
        try container.encode(summary, forKey: .summary)
        try container.encode(evidenceExcerpt, forKey: .evidenceExcerpt)
        try container.encode(deduplicationHint, forKey: .deduplicationHint)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(relatedScreenshotIDs, forKey: .relatedScreenshotIDs)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(requiresReview, forKey: .requiresReview)
        try container.encode(isSelectedForExport, forKey: .isSelectedForExport)
        try container.encodeIfPresent(sectionTitle, forKey: .sectionTitle)
        try container.encode(reproductionSteps, forKey: .reproductionSteps)
        try container.encode(screenshotAnnotations, forKey: .screenshotAnnotations)
        try container.encodeIfPresent(note, forKey: .note)
        try container.encodeIfPresent(gitHubExportTarget, forKey: .gitHubExportTarget)
        try container.encodeIfPresent(jiraExportTarget, forKey: .jiraExportTarget)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case severity
        case component
        case summary
        case evidenceExcerpt
        case deduplicationHint
        case timestamp
        case relatedScreenshotIDs
        case confidence
        case requiresReview
        case isSelectedForExport
        case sectionTitle
        case reproductionSteps
        case screenshotAnnotations
        case note
        case gitHubExportTarget
        case jiraExportTarget
    }

    var timestampLabel: String? {
        guard let timestamp else {
            return nil
        }

        return ElapsedTimeFormatter.string(from: timestamp)
    }

    var confidenceLabel: String? {
        guard let confidence else {
            return nil
        }

        return "\(Int((confidence * 100).rounded()))%"
    }

    func screenshotAnnotations(for screenshotID: UUID) -> [IssueScreenshotAnnotation] {
        screenshotAnnotations.filter { $0.screenshotID == screenshotID }
    }

    static func makeDeduplicationHint(title: String, summary: String, evidenceExcerpt: String) -> String {
        let normalized = [
            title,
            summary,
            evidenceExcerpt
        ]
        .joined(separator: "\n")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: deduplicationNormalizationLocale)
        .lowercased(with: deduplicationNormalizationLocale)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else {
            return "issue-0000000000000000"
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= prime
        }

        return String(format: "issue-%016llx", hash)
    }

    private static func normalizedDeduplicationHint(
        _ value: String?,
        title: String,
        summary: String,
        evidenceExcerpt: String
    ) -> String {
        if let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmedValue.isEmpty {
            return trimmedValue
        }

        return makeDeduplicationHint(title: title, summary: summary, evidenceExcerpt: evidenceExcerpt)
    }
}

