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
