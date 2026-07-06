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

struct ReviewWorkspaceTimelineEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: TimeInterval
    let kind: ReviewWorkspaceTimelineEntryKind
    let title: String?
    let text: String
    let secondaryText: String?
    let index: Int?
    let screenshotID: UUID?

    var timeLabel: String {
        ElapsedTimeFormatter.string(from: timestamp)
    }
}

enum ReviewWorkspaceTimelineEntryKind: Equatable {
    case transcript
    case marker
    case screenshot

    var sortPriority: Int {
        switch self {
        case .transcript:
            return 2
        case .marker:
            return 0
        case .screenshot:
            return 1
        }
    }
}
