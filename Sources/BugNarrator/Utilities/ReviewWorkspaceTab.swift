import Foundation

enum ReviewWorkspaceTab: Identifiable, CaseIterable {
    case rawTranscript
    case reviewSummary
    case screenshots
    case extractedIssues

    var id: String { title }

    var title: String {
        switch self {
        case .rawTranscript:
            return "Transcript"
        case .reviewSummary:
            return "Summary"
        case .screenshots:
            return "Screenshots"
        case .extractedIssues:
            return "Extracted Issues"
        }
    }
}
