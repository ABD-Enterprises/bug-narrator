import Foundation

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

