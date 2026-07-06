import Foundation

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
