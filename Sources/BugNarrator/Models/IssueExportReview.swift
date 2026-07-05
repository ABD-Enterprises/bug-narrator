import Foundation

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
