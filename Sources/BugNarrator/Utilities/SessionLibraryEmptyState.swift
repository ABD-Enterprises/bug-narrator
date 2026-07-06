import Foundation

enum SessionLibraryEmptyState: Equatable {
    case noSessionsYet
    case noSessionsInFilter(SessionLibraryDateFilter)
    case noSessionsInCustomRange
    case noSearchResults

    var title: String {
        switch self {
        case .noSessionsYet:
            return "No Sessions Yet"
        case .noSessionsInFilter(let filter):
            if filter == .retryNeeded {
                return "No Retry Needed Sessions"
            }
            return "No Sessions in \(filter.rawValue)"
        case .noSessionsInCustomRange:
            return "No Sessions in Date Range"
        case .noSearchResults:
            return "No Matching Sessions"
        }
    }

    var description: String {
        switch self {
        case .noSessionsYet:
            return "Start and stop a feedback session to begin building your BugNarrator session library."
        case .noSessionsInFilter(let filter):
            if filter == .retryNeeded {
                return "No saved sessions are currently waiting for transcription retry."
            }
            return "No saved sessions match \(filter.rawValue.lowercased()) yet."
        case .noSessionsInCustomRange:
            return "Widen the selected date range to include more sessions."
        case .noSearchResults:
            return "Try a different search term or clear search to see more sessions."
        }
    }

    var systemImage: String {
        switch self {
        case .noSessionsYet:
            return "text.quote"
        case .noSessionsInFilter(let filter):
            return filter == .retryNeeded ? "arrow.clockwise.circle" : "calendar.badge.exclamationmark"
        case .noSessionsInCustomRange:
            return "calendar.badge.exclamationmark"
        case .noSearchResults:
            return "magnifyingglass"
        }
    }
}
