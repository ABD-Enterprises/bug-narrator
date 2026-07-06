import Foundation

struct ReviewSummaryIssueGroup: Equatable {
    let category: ExtractedIssueCategory
    let issues: [ExtractedIssue]

    var title: String {
        switch category {
        case .bug:
            return "Bugs"
        case .uxIssue:
            return "UX Issues"
        case .enhancement:
            return "Enhancements"
        case .followUp:
            return "Questions / Follow-ups"
        }
    }
}
