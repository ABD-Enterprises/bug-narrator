import Foundation

protocol SessionLibraryItem: Identifiable {
    var id: UUID { get }
    var createdAt: Date { get }
    var searchIndexText: String { get }
}

struct SessionLibraryEntry: SessionLibraryItem, Equatable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let title: String
    let preview: String
    let summaryText: String
    let duration: TimeInterval
    let markerCount: Int
    let screenshotCount: Int
    let issueCount: Int
    let isPendingTranscription: Bool
    let searchIndexText: String

    init(session: TranscriptSession) {
        id = session.id
        createdAt = session.createdAt
        updatedAt = session.updatedAt
        title = session.title
        preview = session.preview
        summaryText = session.summaryText
        duration = session.duration
        markerCount = session.markerCount
        screenshotCount = session.screenshotCount
        issueCount = session.issueCount
        isPendingTranscription = session.requiresTranscriptionRetry
        searchIndexText = session.searchIndexText
    }
}

struct SessionLibrarySnapshot<Item: SessionLibraryItem> {
    let filteredItems: [Item]
    let counts: [SessionLibraryDateFilter: Int]
    let emptyState: SessionLibraryEmptyState?
}

enum SessionLibraryDateFilter: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case last7Days = "Last 7 Days"
    case last30Days = "Last 30 Days"
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
        case .noSessionsInFilter, .noSessionsInCustomRange:
            return "calendar.badge.exclamationmark"
        case .noSearchResults:
            return "magnifyingglass"
        }
    }
}

enum SessionLibrary {
    static func snapshot<Item: SessionLibraryItem>(
        from items: [Item],
        query: SessionLibraryQuery,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> SessionLibrarySnapshot<Item> {
        let searchText = normalizedSearchText(query.searchText)
        var counts = Dictionary(uniqueKeysWithValues: SessionLibraryDateFilter.allCases.map { ($0, 0) })
        counts[.allSessions] = items.count
        var filteredItems: [Item] = []

        for item in items {
            let membership = dateMembership(
                for: item.createdAt,
                customDateRange: query.customDateRange,
                calendar: calendar,
                referenceDate: referenceDate
            )

            if membership.today {
                counts[.today, default: 0] += 1
            }
            if membership.yesterday {
                counts[.yesterday, default: 0] += 1
            }
            if membership.last7Days {
                counts[.last7Days, default: 0] += 1
            }
            if membership.last30Days {
                counts[.last30Days, default: 0] += 1
            }
            if membership.customRange {
                counts[.customRange, default: 0] += 1
            }

            guard membership.matches(query.filter) else {
                continue
            }

            if !searchText.isEmpty && !item.searchIndexText.contains(searchText) {
                continue
            }

            filteredItems.append(item)
        }

        filteredItems.sort { lhs, rhs in
            switch query.sortOrder {
            case .newestFirst:
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }
                return lhs.createdAt > rhs.createdAt
            case .oldestFirst:
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.createdAt < rhs.createdAt
            }
        }

        return SessionLibrarySnapshot(
            filteredItems: filteredItems,
            counts: counts,
            emptyState: emptyState(
                allSessionCount: items.count,
                filteredSessionCount: filteredItems.count,
                query: query
            )
        )
    }

    static func filteredSessions(
        from sessions: [TranscriptSession],
        query: SessionLibraryQuery,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [TranscriptSession] {
        snapshot(from: sessions, query: query, calendar: calendar, referenceDate: referenceDate).filteredItems
    }

    static func filteredEntries(
        from entries: [SessionLibraryEntry],
        query: SessionLibraryQuery,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> [SessionLibraryEntry] {
        snapshot(from: entries, query: query, calendar: calendar, referenceDate: referenceDate).filteredItems
    }

    static func count<Item: SessionLibraryItem>(
        for filter: SessionLibraryDateFilter,
        in items: [Item],
        customDateRange: SessionLibraryDateRange,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Int {
        snapshot(
            from: items,
            query: SessionLibraryQuery(
                filter: .allSessions,
                customDateRange: customDateRange
            ),
            calendar: calendar,
            referenceDate: referenceDate
        ).counts[filter] ?? 0
    }

    static func emptyState(
        allSessions: [TranscriptSession],
        filteredSessions: [TranscriptSession],
        query: SessionLibraryQuery
    ) -> SessionLibraryEmptyState? {
        emptyState(
            allSessionCount: allSessions.count,
            filteredSessionCount: filteredSessions.count,
            query: query
        )
    }

    private static func emptyState(
        allSessionCount: Int,
        filteredSessionCount: Int,
        query: SessionLibraryQuery
    ) -> SessionLibraryEmptyState? {
        guard filteredSessionCount == 0 else {
            return nil
        }

        guard allSessionCount > 0 else {
            return .noSessionsYet
        }

        if !normalizedSearchText(query.searchText).isEmpty {
            return .noSearchResults
        }

        switch query.filter {
        case .customRange:
            return .noSessionsInCustomRange
        case .allSessions:
            return .noSessionsYet
        default:
            return .noSessionsInFilter(query.filter)
        }
    }

    private static func dateMembership(
        for createdAt: Date,
        customDateRange: SessionLibraryDateRange,
        calendar: Calendar,
        referenceDate: Date
    ) -> SessionLibraryDateMembership {
        SessionLibraryDateMembership(
            today: calendar.isDate(createdAt, inSameDayAs: referenceDate),
            yesterday: calendar.isDate(
                createdAt,
                inSameDayAs: calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            ),
            last7Days: recentWindow(dayCount: 7, calendar: calendar, referenceDate: referenceDate).contains(createdAt),
            last30Days: recentWindow(dayCount: 30, calendar: calendar, referenceDate: referenceDate).contains(createdAt),
            customRange: customDateRange.normalized(in: calendar).contains(createdAt)
        )
    }

    private static func recentWindow(
        dayCount: Int,
        calendar: Calendar,
        referenceDate: Date
    ) -> ClosedRange<Date> {
        let startOfReferenceDate = calendar.startOfDay(for: referenceDate)
        let lowerBound = calendar.date(byAdding: .day, value: -(dayCount - 1), to: startOfReferenceDate) ?? startOfReferenceDate
        let upperBound = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfReferenceDate) ?? referenceDate
        return lowerBound ... upperBound
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private struct SessionLibraryDateMembership {
    let today: Bool
    let yesterday: Bool
    let last7Days: Bool
    let last30Days: Bool
    let customRange: Bool

    func matches(_ filter: SessionLibraryDateFilter) -> Bool {
        switch filter {
        case .today:
            return today
        case .yesterday:
            return yesterday
        case .last7Days:
            return last7Days
        case .last30Days:
            return last30Days
        case .allSessions:
            return true
        case .customRange:
            return customRange
        }
    }
}
