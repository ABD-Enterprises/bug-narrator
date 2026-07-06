import Foundation

enum SessionLibraryDateFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case retryNeeded = "Retry Needed"
    case allSessions = "All Sessions"
    case customRange = "Custom Date Range"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .today:
            return "sun.max"
        case .yesterday:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .last7Days:
            return "calendar"
        case .last30Days:
            return "calendar.badge.clock"
        case .retryNeeded:
            return "arrow.clockwise.circle"
        case .allSessions:
            return "square.stack.3d.up"
        case .customRange:
            return "calendar.badge.plus"
        }
    }
}

enum SessionLibrarySortOrder: String, CaseIterable, Identifiable {
    case newestFirst = "Newest First"
    case oldestFirst = "Oldest First"

    var id: String { rawValue }
}

struct SessionLibraryDateRange: Equatable {
    var startDate: Date
    var endDate: Date

    func normalized(in calendar: Calendar) -> ClosedRange<Date> {
        let lowerBound = min(startDate, endDate)
        let upperBound = max(startDate, endDate)
        let startOfLowerBound = calendar.startOfDay(for: lowerBound)
        let startOfUpperBound = calendar.startOfDay(for: upperBound)
        let inclusiveUpperBound = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfUpperBound)
            ?? upperBound
        return startOfLowerBound ... inclusiveUpperBound
    }
}

struct SessionLibraryQuery: Equatable {
    var filter: SessionLibraryDateFilter
    var customDateRange: SessionLibraryDateRange
    var searchText: String = ""
    var sortOrder: SessionLibrarySortOrder = .newestFirst
}
