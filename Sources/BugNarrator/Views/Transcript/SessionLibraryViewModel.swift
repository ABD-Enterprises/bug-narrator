import Foundation
import SwiftUI

/// View model for the session library sidebar (#631, closes #401 slice d).
/// Owns the filter/search/sort/date-range state and the derived query
/// helpers. Both `SessionListSidebar` and `TranscriptView.detailPane`
/// observe the same VM so the detail pane sees the same `selectedSession`
/// / `emptyState` that the sidebar produces.
@MainActor
final class SessionLibraryViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var sortOrder: SessionLibrarySortOrder = .newestFirst
    @Published var selectedFilter: SessionLibraryDateFilter = .today
    @Published var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @Published var customEndDate: Date = Date()
    @Published private(set) var hasResolvedInitialFilter: Bool = false

    let calendar: Calendar

    private unowned let appState: AppState
    private unowned let transcriptStore: TranscriptStore

    init(
        appState: AppState,
        transcriptStore: TranscriptStore,
        calendar: Calendar = .current
    ) {
        self.appState = appState
        self.transcriptStore = transcriptStore
        self.calendar = calendar
    }

    // MARK: - Derived state (read by sidebar + detail pane)

    var allSessions: [TranscriptSession] {
        var sessions = transcriptStore.sessions

        if let currentTranscript = appState.currentTranscript {
            if let existingIndex = sessions.firstIndex(where: { $0.id == currentTranscript.id }) {
                sessions[existingIndex] = currentTranscript
            } else if !appState.currentTranscriptIsPersisted {
                sessions.insert(currentTranscript, at: 0)
            }
        }

        return sessions
    }

    var allSessionEntries: [SessionLibraryEntry] {
        var entries = transcriptStore.libraryEntries

        if let currentTranscript = appState.currentTranscript {
            let entry = SessionLibraryEntry(session: currentTranscript)
            if let existingIndex = entries.firstIndex(where: { $0.id == currentTranscript.id }) {
                entries[existingIndex] = entry
            } else if !appState.currentTranscriptIsPersisted {
                entries.insert(entry, at: 0)
            }
        }

        return entries
    }

    var query: SessionLibraryQuery {
        SessionLibraryQuery(
            filter: selectedFilter,
            customDateRange: SessionLibraryDateRange(startDate: customStartDate, endDate: customEndDate),
            searchText: searchText,
            sortOrder: sortOrder
        )
    }

    var librarySnapshot: SessionLibrarySnapshot<SessionLibraryEntry> {
        SessionLibrary.snapshot(
            from: allSessionEntries,
            query: query,
            calendar: calendar
        )
    }

    var filteredEntries: [SessionLibraryEntry] {
        librarySnapshot.filteredItems
    }

    var selectedSession: TranscriptSession? {
        guard let selectedTranscriptID = appState.selectedTranscriptID else {
            return filteredEntries.first.flatMap { resolveSession(for: $0) }
        }

        guard let selectedEntry = filteredEntries.first(where: { $0.id == selectedTranscriptID }) else {
            return filteredEntries.first.flatMap { resolveSession(for: $0) }
        }

        return resolveSession(for: selectedEntry)
    }

    var emptyState: SessionLibraryEmptyState? {
        librarySnapshot.emptyState
    }

    var sessionCountSummary: String {
        let count = filteredEntries.count
        let pendingRetryCount = transcriptStore.pendingTranscriptionSessionCount
        let pendingRetrySuffix: String
        if pendingRetryCount > 0 {
            pendingRetrySuffix = pendingRetryCount == 1
                ? " • 1 needs retry"
                : " • \(pendingRetryCount) need retry"
        } else {
            pendingRetrySuffix = ""
        }

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (count == 1 ? "1 session" : "\(count) sessions") + pendingRetrySuffix
        }

        return (count == 1 ? "1 result for “\(searchText)”" : "\(count) results for “\(searchText)”") + pendingRetrySuffix
    }

    var sessionIDSignature: String {
        allSessionEntries.map(\.id.uuidString).joined(separator: "|")
    }

    func count(for filter: SessionLibraryDateFilter) -> Int {
        librarySnapshot.counts[filter] ?? 0
    }

    // MARK: - Callbacks

    func resolveInitialFilterIfNeeded() {
        guard !hasResolvedInitialFilter else {
            return
        }

        hasResolvedInitialFilter = true
        if count(for: .today) == 0, count(for: .retryNeeded) > 0 {
            selectedFilter = .retryNeeded
        } else if count(for: .today) == 0, !allSessionEntries.isEmpty {
            selectedFilter = .allSessions
        }
    }

    func syncSelection() {
        guard !filteredEntries.isEmpty else {
            appState.selectedTranscriptID = nil
            return
        }

        if let selectedTranscriptID = appState.selectedTranscriptID,
           filteredEntries.contains(where: { $0.id == selectedTranscriptID }) {
            return
        }

        appState.selectedTranscriptID = filteredEntries.first?.id
    }

    func openLatestPendingTranscriptionSession() {
        selectedFilter = .retryNeeded
        searchText = ""
        appState.selectedTranscriptID = transcriptStore.latestPendingTranscriptionSession?.id
        syncSelection()
    }

    // MARK: - Session resolution (mirrors TranscriptSharedHelpers)

    private func resolveSession(for entry: SessionLibraryEntry) -> TranscriptSession? {
        if appState.currentTranscript?.id == entry.id {
            return appState.currentTranscript
        }

        return transcriptStore.session(with: entry.id)
    }
}
