import Foundation
import XCTest
@testable import BugNarrator

final class SessionLibraryTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-03-14T12:00:00Z")!

    func testDateBucketFilteringReturnsExpectedSessions() {
        let calendar = makeCalendar()
        let sessions = makeDatedSessions()
        let dateRange = SessionLibraryDateRange(
            startDate: referenceDate.addingTimeInterval(-7 * 24 * 60 * 60),
            endDate: referenceDate
        )

        let todaySessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(filter: .today, customDateRange: dateRange),
            calendar: calendar,
            referenceDate: referenceDate
        )
        let yesterdaySessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(filter: .yesterday, customDateRange: dateRange),
            calendar: calendar,
            referenceDate: referenceDate
        )
        let last7DaysSessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(filter: .last7Days, customDateRange: dateRange),
            calendar: calendar,
            referenceDate: referenceDate
        )
        let last30DaysSessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(filter: .last30Days, customDateRange: dateRange),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(todaySessions.map(\.transcript), ["Today transcript"])
        XCTAssertEqual(yesterdaySessions.map(\.transcript), ["Yesterday transcript"])
        XCTAssertEqual(last7DaysSessions.map(\.transcript), ["Today transcript", "Yesterday transcript", "Five days ago transcript"])
        XCTAssertEqual(last30DaysSessions.map(\.transcript), ["Today transcript", "Yesterday transcript", "Five days ago transcript", "Twenty days ago transcript"])
    }

    func testCustomDateRangeFilteringAndSearchWorkTogether() {
        let calendar = makeCalendar()
        let sessionInRange = makeSession(
            transcript: "Tooltip jumps under cursor.",
            createdAt: ISO8601DateFormatter().date(from: "2026-02-22T14:00:00Z")!,
            summary: "One UX issue around the checkout tooltip."
        )
        let sessionOutOfRange = makeSession(
            transcript: "Sidebar focus disappears.",
            createdAt: ISO8601DateFormatter().date(from: "2026-01-05T14:00:00Z")!,
            summary: "Focus bug."
        )
        let query = SessionLibraryQuery(
            filter: .customRange,
            customDateRange: SessionLibraryDateRange(
                startDate: ISO8601DateFormatter().date(from: "2026-02-20T00:00:00Z")!,
                endDate: ISO8601DateFormatter().date(from: "2026-02-28T23:59:59Z")!
            ),
            searchText: "tooltip",
            sortOrder: .newestFirst
        )

        let filteredSessions = SessionLibrary.filteredSessions(
            from: [sessionOutOfRange, sessionInRange],
            query: query,
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(filteredSessions, [sessionInRange])
    }

    func testSearchMatchesTitleTranscriptAndSummary() {
        let calendar = makeCalendar()
        let titleMatch = makeSession(
            transcript: "Checkout regression in payment modal. Plain transcript.",
            createdAt: referenceDate,
            summary: ""
        )
        let transcriptMatch = makeSession(
            transcript: "General review. Tooltip jumps under cursor during hover.",
            createdAt: referenceDate.addingTimeInterval(-60),
            summary: ""
        )
        let summaryMatch = makeSession(
            transcript: "Plain transcript",
            createdAt: referenceDate.addingTimeInterval(-120),
            summary: "The summary mentions tooltip behavior."
        )

        let filteredSessions = SessionLibrary.filteredSessions(
            from: [titleMatch, transcriptMatch, summaryMatch],
            query: SessionLibraryQuery(
                filter: .allSessions,
                customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate),
                searchText: "tooltip",
                sortOrder: .newestFirst
            ),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(filteredSessions, [transcriptMatch, summaryMatch])

        let titleFilteredSessions = SessionLibrary.filteredSessions(
            from: [titleMatch, transcriptMatch, summaryMatch],
            query: SessionLibraryQuery(
                filter: .allSessions,
                customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate),
                searchText: "checkout",
                sortOrder: .newestFirst
            ),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(titleFilteredSessions, [titleMatch])
    }

    func testSortOrderCanSwitchToOldestFirst() {
        let calendar = makeCalendar()
        let sessions = makeDatedSessions()

        let filteredSessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(
                filter: .last30Days,
                customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate),
                sortOrder: .oldestFirst
            ),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(
            filteredSessions.map(\.transcript),
            ["Twenty days ago transcript", "Five days ago transcript", "Yesterday transcript", "Today transcript"]
        )
    }

    func testFilterCountsReflectUnderlyingSessions() {
        let calendar = makeCalendar()
        let sessions = makeDatedSessions()
        let customDateRange = SessionLibraryDateRange(
            startDate: ISO8601DateFormatter().date(from: "2026-02-20T00:00:00Z")!,
            endDate: ISO8601DateFormatter().date(from: "2026-02-28T23:59:59Z")!
        )

        XCTAssertEqual(SessionLibrary.count(for: .today, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 1)
        XCTAssertEqual(SessionLibrary.count(for: .yesterday, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 1)
        XCTAssertEqual(SessionLibrary.count(for: .last7Days, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 3)
        XCTAssertEqual(SessionLibrary.count(for: .last30Days, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 4)
        XCTAssertEqual(SessionLibrary.count(for: .allSessions, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 5)
        XCTAssertEqual(SessionLibrary.count(for: .customRange, in: sessions, customDateRange: customDateRange, calendar: calendar, referenceDate: referenceDate), 1)
    }

    func testDateBucketFilteringHandlesMidnightBoundariesInLocalTimezone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let formatter = ISO8601DateFormatter()
        let referenceDate = formatter.date(from: "2026-03-14T00:30:00-04:00")!
        let sessions = [
            makeSession(
                transcript: "Just after midnight transcript",
                createdAt: formatter.date(from: "2026-03-14T00:05:00-04:00")!,
                summary: ""
            ),
            makeSession(
                transcript: "Just before midnight transcript",
                createdAt: formatter.date(from: "2026-03-13T23:55:00-04:00")!,
                summary: ""
            )
        ]
        let query = SessionLibraryQuery(
            filter: .today,
            customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate)
        )

        let todaySessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: query,
            calendar: calendar,
            referenceDate: referenceDate
        )
        let yesterdaySessions = SessionLibrary.filteredSessions(
            from: sessions,
            query: SessionLibraryQuery(
                filter: .yesterday,
                customDateRange: query.customDateRange
            ),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(todaySessions.map(\.transcript), ["Just after midnight transcript"])
        XCTAssertEqual(yesterdaySessions.map(\.transcript), ["Just before midnight transcript"])
    }

    func testEmptyStateCoversNoSessionsNoResultsAndNoFilterMatches() {
        let emptyQuery = SessionLibraryQuery(
            filter: .allSessions,
            customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate)
        )

        XCTAssertEqual(
            SessionLibrary.emptyState(allSessions: [], filteredSessions: [], query: emptyQuery),
            .noSessionsYet
        )

        let sessions = [
            makeSession(
                transcript: "Transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-01-05T14:00:00Z")!,
                summary: ""
            )
        ]

        XCTAssertEqual(
            SessionLibrary.emptyState(
                allSessions: sessions,
                filteredSessions: [],
                query: SessionLibraryQuery(
                    filter: .today,
                    customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate)
                )
            ),
            .noSessionsInFilter(.today)
        )

        XCTAssertEqual(
            SessionLibrary.emptyState(
                allSessions: sessions,
                filteredSessions: [],
                query: SessionLibraryQuery(
                    filter: .customRange,
                    customDateRange: SessionLibraryDateRange(
                        startDate: ISO8601DateFormatter().date(from: "2026-02-20T00:00:00Z")!,
                        endDate: ISO8601DateFormatter().date(from: "2026-02-28T23:59:59Z")!
                    )
                )
            ),
            .noSessionsInCustomRange
        )

        XCTAssertEqual(
            SessionLibrary.emptyState(
                allSessions: sessions,
                filteredSessions: [],
                query: SessionLibraryQuery(
                    filter: .allSessions,
                    customDateRange: SessionLibraryDateRange(startDate: referenceDate, endDate: referenceDate),
                    searchText: "tooltip"
                )
            ),
            .noSearchResults
        )
    }

    func testSnapshotSupportsIndexedEntriesForLargeHistory() {
        let calendar = makeCalendar()
        let sessions = (0..<1_000).map { index in
            makeSession(
                transcript: index.isMultiple(of: 125) ? "Critical checkout tooltip regression \(index)" : "Transcript \(index)",
                createdAt: referenceDate.addingTimeInterval(TimeInterval(-index * 60)),
                summary: index.isMultiple(of: 200) ? "Tooltip summary \(index)" : ""
            )
        }
        let entries = sessions.map(SessionLibraryEntry.init(session:))
        let snapshot = SessionLibrary.snapshot(
            from: entries,
            query: SessionLibraryQuery(
                filter: .allSessions,
                customDateRange: SessionLibraryDateRange(
                    startDate: referenceDate.addingTimeInterval(-40 * 24 * 60 * 60),
                    endDate: referenceDate
                ),
                searchText: "tooltip",
                sortOrder: .newestFirst
            ),
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(snapshot.counts[.allSessions], 1_000)
        XCTAssertEqual(snapshot.filteredItems.count, 12)
        XCTAssertEqual(snapshot.filteredItems.first?.title, SessionLibraryEntry(session: sessions[0]).title)
    }

    func testDisplayTitleFallsBackToUntitledSessionWhenTranscriptIsBlank() {
        XCTAssertEqual(TranscriptSession.displayTitle(from: "   \n  "), "Untitled Session")
    }

    func testPreviewTextTruncatesAtWordBoundaryWithEllipsis() {
        let transcript = Array(repeating: "checkout tooltip evidence", count: 20).joined(separator: " ")
        let preview = TranscriptSession.previewText(from: transcript)

        XCTAssertLessThanOrEqual(preview.count, 161)
        XCTAssertTrue(preview.hasSuffix("…"))
        XCTAssertFalse(preview.hasSuffix(" "))
    }

    private func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDatedSessions() -> [TranscriptSession] {
        [
            makeSession(
                transcript: "Today transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-03-14T09:00:00Z")!,
                summary: ""
            ),
            makeSession(
                transcript: "Yesterday transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-03-13T09:00:00Z")!,
                summary: ""
            ),
            makeSession(
                transcript: "Five days ago transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-03-09T09:00:00Z")!,
                summary: ""
            ),
            makeSession(
                transcript: "Twenty days ago transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-02-22T09:00:00Z")!,
                summary: ""
            ),
            makeSession(
                transcript: "Older transcript",
                createdAt: ISO8601DateFormatter().date(from: "2026-01-20T09:00:00Z")!,
                summary: ""
            )
        ]
    }

    private func makeSession(
        transcript: String,
        createdAt: Date,
        summary: String
    ) -> TranscriptSession {
        TranscriptSession(
            createdAt: createdAt,
            transcript: transcript,
            duration: 45,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            issueExtraction: summary.isEmpty ? nil : IssueExtractionResult(summary: summary, issues: []),
            updatedAt: createdAt
        )
    }
}
