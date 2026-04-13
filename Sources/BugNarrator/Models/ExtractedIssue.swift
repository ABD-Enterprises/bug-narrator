import Foundation

enum ExtractedIssueCategory: String, Codable, CaseIterable, Identifiable {
    case bug = "Bug"
    case uxIssue = "UX Issue"
    case enhancement = "Enhancement"
    case followUp = "Question / Follow-up"

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

struct ExtractedIssue: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var category: ExtractedIssueCategory
    var summary: String
    var evidenceExcerpt: String
    var timestamp: TimeInterval?
    var relatedScreenshotIDs: [UUID]
    var confidence: Double?
    var requiresReview: Bool
    var isSelectedForExport: Bool
    var sectionTitle: String?
    var reproductionSteps: [IssueReproductionStep]
    var note: String?

    init(
        id: UUID = UUID(),
        title: String,
        category: ExtractedIssueCategory,
        summary: String,
        evidenceExcerpt: String,
        timestamp: TimeInterval?,
        relatedScreenshotIDs: [UUID] = [],
        confidence: Double? = nil,
        requiresReview: Bool = true,
        isSelectedForExport: Bool = true,
        sectionTitle: String? = nil,
        reproductionSteps: [IssueReproductionStep] = [],
        note: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.summary = summary
        self.evidenceExcerpt = evidenceExcerpt
        self.timestamp = timestamp
        self.relatedScreenshotIDs = relatedScreenshotIDs
        self.confidence = confidence
        self.requiresReview = requiresReview
        self.isSelectedForExport = isSelectedForExport
        self.sectionTitle = sectionTitle
        self.reproductionSteps = reproductionSteps
        self.note = note
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(ExtractedIssueCategory.self, forKey: .category)
        summary = try container.decode(String.self, forKey: .summary)
        evidenceExcerpt = try container.decode(String.self, forKey: .evidenceExcerpt)
        timestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .timestamp)
        relatedScreenshotIDs = try container.decodeIfPresent([UUID].self, forKey: .relatedScreenshotIDs) ?? []
        confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        requiresReview = try container.decodeIfPresent(Bool.self, forKey: .requiresReview) ?? true
        isSelectedForExport = try container.decodeIfPresent(Bool.self, forKey: .isSelectedForExport) ?? true
        sectionTitle = try container.decodeIfPresent(String.self, forKey: .sectionTitle)
        reproductionSteps = try container.decodeIfPresent([IssueReproductionStep].self, forKey: .reproductionSteps) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encode(summary, forKey: .summary)
        try container.encode(evidenceExcerpt, forKey: .evidenceExcerpt)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encode(relatedScreenshotIDs, forKey: .relatedScreenshotIDs)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encode(requiresReview, forKey: .requiresReview)
        try container.encode(isSelectedForExport, forKey: .isSelectedForExport)
        try container.encodeIfPresent(sectionTitle, forKey: .sectionTitle)
        try container.encode(reproductionSteps, forKey: .reproductionSteps)
        try container.encodeIfPresent(note, forKey: .note)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case category
        case summary
        case evidenceExcerpt
        case timestamp
        case relatedScreenshotIDs
        case confidence
        case requiresReview
        case isSelectedForExport
        case sectionTitle
        case reproductionSteps
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

struct GitHubExportConfiguration: Equatable {
    let token: String
    let owner: String
    let repository: String
    let labels: [String]

    var isComplete: Bool {
        !token.isEmpty && !owner.isEmpty && !repository.isEmpty
    }
}

struct JiraExportConfiguration: Equatable {
    let baseURL: URL
    let email: String
    let apiToken: String
    let projectKey: String
    let issueType: String

    var isComplete: Bool {
        !email.isEmpty && !apiToken.isEmpty && !projectKey.isEmpty && !issueType.isEmpty
    }
}
