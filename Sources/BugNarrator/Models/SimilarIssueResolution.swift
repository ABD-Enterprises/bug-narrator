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
