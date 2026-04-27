import Foundation

enum ExtractedIssueCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case uxIssue = "UX Issue"
    case enhancement = "Enhancement"
    case followUp = "Question / Follow-up"

    var id: String { rawValue }
}

enum ExtractedIssueSeverity: String, Codable, CaseIterable, Identifiable {
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }
}

struct IssueReproductionStep: Identifiable, Codable, Equatable {
    let id: UUID
    var instruction: String
    var expectedResult: String?
    var actualResult: String?
    var timestamp: TimeInterval?
    var screenshotID: UUID?

    init(
        id: UUID = UUID(),
        instruction: String,
        expectedResult: String? = nil,
        actualResult: String? = nil,
        timestamp: TimeInterval? = nil,
        screenshotID: UUID? = nil
    ) {
        self.id = id
        self.instruction = instruction
        self.expectedResult = expectedResult
        self.actualResult = actualResult
        self.timestamp = timestamp
        self.screenshotID = screenshotID
    }

    var timestampLabel: String? {
        guard let timestamp else {
            return nil
        }

        return ElapsedTimeFormatter.string(from: timestamp)
    }
}

struct IssueScreenshotAnnotation: Identifiable, Codable, Equatable {
    enum Style: String, Codable {
        case highlight
    }

    let id: UUID
    var screenshotID: UUID
    var label: String?
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var confidence: Double?
    var style: Style

    init(
        id: UUID = UUID(),
        screenshotID: UUID,
        label: String? = nil,
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        confidence: Double? = nil,
        style: Style = .highlight
    ) {
        self.id = id
        self.screenshotID = screenshotID
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.x = min(max(x, 0), 1)
        self.y = min(max(y, 0), 1)
        self.width = min(max(width, 0.05), 1)
        self.height = min(max(height, 0.05), 1)
        self.confidence = confidence
        self.style = style

        clampRectIntoBounds()
    }

    var normalizedRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    var confidenceLabel: String? {
        guard let confidence else {
            return nil
        }

        return "\(Int((confidence * 100).rounded()))%"
    }

    var exportDescription: String {
        let normalized = normalizedRect
        let xPercent = Int((normalized.minX * 100).rounded())
        let yPercent = Int((normalized.minY * 100).rounded())
        let widthPercent = Int((normalized.width * 100).rounded())
        let heightPercent = Int((normalized.height * 100).rounded())

        var parts = [
            label ?? "UI highlight",
            "x \(xPercent)%",
            "y \(yPercent)%",
            "w \(widthPercent)%",
            "h \(heightPercent)%"
        ]

        if let confidenceLabel {
            parts.append("confidence \(confidenceLabel)")
        }

        return parts.joined(separator: " • ")
    }

    mutating func move(x deltaX: Double, y deltaY: Double) {
        x += deltaX
        y += deltaY
        clampRectIntoBounds()
    }

    mutating func updateRect(_ rect: CGRect) {
        x = min(max(rect.origin.x, 0), 1)
        y = min(max(rect.origin.y, 0), 1)
        width = min(max(rect.width, 0.05), 1)
        height = min(max(rect.height, 0.05), 1)
        clampRectIntoBounds()
    }

    private mutating func clampRectIntoBounds() {
        width = min(max(width, 0.05), 1)
        height = min(max(height, 0.05), 1)
        x = min(max(x, 0), max(0, 1 - width))
        y = min(max(y, 0), max(0, 1 - height))
    }
}

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
        note: String? = nil
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

struct IssueExtractionResult: Codable, Equatable {
    let generatedAt: Date
    var summary: String
    var guidanceNote: String
    var issues: [ExtractedIssue]

    init(
        generatedAt: Date = Date(),
        summary: String,
        guidanceNote: String = "Extracted issues are draft suggestions and should be reviewed before export.",
        issues: [ExtractedIssue]
    ) {
        self.generatedAt = generatedAt
        self.summary = summary
        self.guidanceNote = guidanceNote
        self.issues = issues
    }

    var selectedIssues: [ExtractedIssue] {
        issues.filter(\.isSelectedForExport)
    }
}

enum ExportDestination: String, Codable, CaseIterable, Identifiable {
    case github = "GitHub"
    case jira = "Jira"

    var id: String { rawValue }

    var actionTitle: String {
        "Export to \(rawValue)"
    }
}

struct ExportResult: Identifiable, Equatable {
    let id: UUID
    let sourceIssueID: UUID
    let destination: ExportDestination
    let remoteIdentifier: String
    let remoteURL: URL?
    let exportedAt: Date

    init(
        id: UUID = UUID(),
        sourceIssueID: UUID,
        destination: ExportDestination,
        remoteIdentifier: String,
        remoteURL: URL?,
        exportedAt: Date = Date()
    ) {
        self.id = id
        self.sourceIssueID = sourceIssueID
        self.destination = destination
        self.remoteIdentifier = remoteIdentifier
        self.remoteURL = remoteURL
        self.exportedAt = exportedAt
    }
}

enum SimilarIssueResolution: String, CaseIterable, Identifiable {
    case exportNew = "Export as New"
    case linkAsRelated = "Link as Related"
    case markDuplicate = "Mark as Duplicate"

    var id: String { rawValue }

    var helpText: String {
        switch self {
        case .exportNew:
            return "Create a brand-new tracker issue."
        case .linkAsRelated:
            return "Create a new issue and reference an existing tracker issue as related context."
        case .markDuplicate:
            return "Skip creating a new issue and use the matched tracker issue instead."
        }
    }
}

struct SimilarIssueMatch: Identifiable, Equatable {
    let id: String
    let remoteIdentifier: String
    let title: String
    let summary: String
    let remoteURL: URL?
    let confidence: Double
    let reasoning: String

    init(
        remoteIdentifier: String,
        title: String,
        summary: String,
        remoteURL: URL?,
        confidence: Double,
        reasoning: String
    ) {
        self.id = remoteIdentifier.lowercased()
        self.remoteIdentifier = remoteIdentifier
        self.title = title
        self.summary = summary
        self.remoteURL = remoteURL
        self.confidence = min(max(confidence, 0), 1)
        self.reasoning = reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

struct IssueExportReviewItem: Identifiable, Equatable {
    let id: UUID
    var issue: ExtractedIssue
    var matches: [SimilarIssueMatch]
    var resolution: SimilarIssueResolution
    var selectedMatchID: String?

    init(
        issue: ExtractedIssue,
        matches: [SimilarIssueMatch],
        resolution: SimilarIssueResolution = .exportNew,
        selectedMatchID: String? = nil
    ) {
        self.id = issue.id
        self.issue = issue
        self.matches = matches
        self.resolution = resolution
        self.selectedMatchID = selectedMatchID ?? matches.first?.id

        if resolution != .exportNew, self.selectedMatchID == nil {
            self.selectedMatchID = matches.first?.id
        }
    }

    var selectedMatch: SimilarIssueMatch? {
        guard let selectedMatchID else {
            return nil
        }

        return matches.first { $0.id == selectedMatchID }
    }

    var hasMatches: Bool {
        !matches.isEmpty
    }

    mutating func setResolution(_ resolution: SimilarIssueResolution) {
        self.resolution = resolution

        guard resolution != .exportNew else {
            return
        }

        if selectedMatch == nil {
            selectedMatchID = matches.first?.id
        }
    }

    mutating func selectMatch(id: String) {
        guard matches.contains(where: { $0.id == id }) else {
            return
        }

        selectedMatchID = id
    }
}

struct IssueExportReview: Identifiable, Equatable {
    let id: UUID
    let destination: ExportDestination
    let sessionID: UUID
    var items: [IssueExportReviewItem]

    init(
        destination: ExportDestination,
        sessionID: UUID,
        items: [IssueExportReviewItem]
    ) {
        self.id = UUID()
        self.destination = destination
        self.sessionID = sessionID
        self.items = items
    }

    var hasMatches: Bool {
        items.contains(where: \.hasMatches)
    }
}

struct GitHubExportConfiguration: Equatable {
    let token: String
    let repositoryID: String?
    let owner: String
    let repository: String
    let labels: [String]

    init(
        token: String,
        repositoryID: String? = nil,
        owner: String,
        repository: String,
        labels: [String]
    ) {
        self.token = token
        self.repositoryID = repositoryID
        self.owner = owner
        self.repository = repository
        self.labels = labels
    }

    var isComplete: Bool {
        !token.isEmpty && !owner.isEmpty && !repository.isEmpty
    }

    var targetIdentity: String {
        repositoryID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "\(owner.lowercased())/\(repository.lowercased())"
    }
}

struct GitHubRepositoryOption: Equatable, Identifiable {
    let repositoryID: String
    let owner: String
    let name: String
    let description: String?

    init(
        repositoryID: String? = nil,
        owner: String,
        name: String,
        description: String?
    ) {
        self.repositoryID = repositoryID ?? "\(owner.lowercased())/\(name.lowercased())"
        self.owner = owner
        self.name = name
        self.description = description
    }

    var id: String { repositoryID }

    var fullName: String {
        "\(owner)/\(name)"
    }

    var displayLabel: String {
        guard let description, !description.isEmpty else {
            return fullName
        }

        return "\(fullName) - \(description)"
    }
}

struct JiraConnectionConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String

    var isComplete: Bool {
        !email.isEmpty && !apiToken.isEmpty
    }
}

struct JiraExportConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String
    let projectID: String?
    let projectKey: String
    let issueTypeID: String
    let issueTypeName: String

    init(
        baseURL: URL,
        email: String,
        apiToken: String,
        projectID: String? = nil,
        projectKey: String,
        issueTypeID: String = "",
        issueTypeName: String? = nil,
        issueType: String? = nil
    ) {
        self.baseURL = baseURL
        self.email = email
        self.apiToken = apiToken
        self.projectID = projectID
        self.projectKey = projectKey
        self.issueTypeID = issueTypeID
        self.issueTypeName = issueTypeName ?? issueType ?? ""
    }

    var isComplete: Bool {
        !email.isEmpty
            && !apiToken.isEmpty
            && !projectKey.isEmpty
            && !(issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 && issueTypeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var targetIdentity: String {
        let normalizedProjectID = projectID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? projectKey.uppercased()
        let normalizedIssueTypeID = issueTypeID.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let normalizedIssueTypeName = issueTypeName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
            ?? "unknown"
        return "\(normalizedProjectID)::\(normalizedIssueTypeID ?? normalizedIssueTypeName)"
    }
}

struct JiraProjectOption: Equatable, Identifiable {
    let projectID: String
    let key: String
    let name: String

    init(projectID: String? = nil, key: String, name: String) {
        self.projectID = projectID ?? key
        self.key = key
        self.name = name
    }

    var id: String { projectID }

    var displayLabel: String {
        "\(key) - \(name)"
    }
}

struct JiraIssueTypeOption: Equatable, Identifiable {
    let id: String
    let name: String
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
