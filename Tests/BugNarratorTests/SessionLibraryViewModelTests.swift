import XCTest
@testable import BugNarrator

/// SessionLibraryViewModel had 0% coverage. Filtering itself is SessionLibrary's
/// job and is tested there. What this view model OWNS — and what a user sees
/// first when the library opens — is: which filter it opens on, how the
/// in-progress recording is merged into the list, which session the detail pane
/// shows, and the count line. All of that was unpinned.
///
/// Dates: sessions that must count as "today" are stamped with a fresh `Date()`
/// at the moment the test runs, never with a value cached at instance creation —
/// XCTest builds every instance before running any, so a cached `now` can be on
/// the other side of midnight by the time the assertion runs. Tests where the
/// date is irrelevant use `.allSessions` so the day boundary cannot matter.
@MainActor
final class SessionLibraryViewModelTests: XCTestCase {

    // MARK: - resolveInitialFilterIfNeeded

    func testInitialFilterStaysOnTodayWhenTodayHasSessionsEvenIfRetriesExist() throws {
        // Retry only outranks "today" when today is EMPTY. A user with work from
        // today must not be yanked off it because an old session needs a retry.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: Date(), transcript: "today"))
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "old", pendingRetry: true))
        let viewModel = makeViewModel(harness)
        XCTAssertFalse(viewModel.hasResolvedInitialFilter)

        viewModel.resolveInitialFilterIfNeeded()

        XCTAssertEqual(viewModel.selectedFilter, .today)
        XCTAssertTrue(viewModel.hasResolvedInitialFilter, "a no-op body would leave this false")
    }

    func testInitialFilterPrefersRetryNeededWhenTodayIsEmptyAndRetriesExist() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "old", pendingRetry: true))
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(5), transcript: "older"))
        let viewModel = makeViewModel(harness)

        viewModel.resolveInitialFilterIfNeeded()

        XCTAssertEqual(viewModel.selectedFilter, .retryNeeded)
    }

    func testInitialFilterFallsBackToAllSessionsWhenTodayIsEmptyAndNothingNeedsRetry() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "old"))
        let viewModel = makeViewModel(harness)

        viewModel.resolveInitialFilterIfNeeded()

        XCTAssertEqual(viewModel.selectedFilter, .allSessions)
    }

    func testInitialFilterStaysOnTodayForAnEmptyLibrary() throws {
        // Nothing to show anywhere: do not flip to an equally empty filter.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let viewModel = makeViewModel(harness)

        viewModel.resolveInitialFilterIfNeeded()

        XCTAssertEqual(viewModel.selectedFilter, .today)
        XCTAssertTrue(viewModel.hasResolvedInitialFilter, "a no-op body would leave this false")
    }

    func testInitialFilterResolvesOnlyOnce() throws {
        // Decided when the library first opens; data arriving later must not
        // yank the filter out from under the user.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let viewModel = makeViewModel(harness)
        viewModel.resolveInitialFilterIfNeeded()
        XCTAssertEqual(viewModel.selectedFilter, .today)

        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "late", pendingRetry: true))
        viewModel.resolveInitialFilterIfNeeded()

        XCTAssertEqual(viewModel.selectedFilter, .today, "second call must be a no-op")
    }

    // MARK: - allSessionEntries: the in-progress recording is merged in

    func testUnpersistedCurrentTranscriptIsInsertedAtTheTop() throws {
        // The recording in progress is not in the store yet. It must still be
        // visible in the sidebar, and first.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let saved = makeSession(createdAt: daysAgo(1), transcript: "saved")
        try harness.transcriptStore.add(saved)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        let live = makeSession(createdAt: daysAgo(2), transcript: "live")  // older than saved: only the merge puts it first

        harness.appState.currentTranscript = live

        XCTAssertFalse(harness.appState.currentTranscriptIsPersisted, "precondition")
        XCTAssertEqual(viewModel.allSessionEntries.first?.id, live.id)
        XCTAssertEqual(viewModel.allSessionEntries.count, 2)
        // allSessions (not just the entries) feeds the empty state and bulk delete;
        // appending instead of inserting at 0 would pass the entries check alone.
        XCTAssertEqual(viewModel.allSessions.first?.id, live.id)
        // The live recording is not in the store, so resolving it through the
        // store yields nil and the detail pane goes blank. resolveSession must
        // short-circuit to the current transcript.
        harness.appState.selectedTranscriptID = live.id
        XCTAssertEqual(viewModel.selectedSession?.id, live.id)
    }

    func testEditedDraftOfAStoredSessionReplacesItsRowInPlace() throws {
        // A draft that shares an id with a stored session must UPDATE that row,
        // not add a second one. (currentTranscriptIsPersisted is VALUE equality
        // with the stored copy, so an edited draft reads as unpersisted — the
        // in-place replacement must key on id, not on that flag.)
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let saved = makeSession(createdAt: daysAgo(1), transcript: "saved")
        try harness.transcriptStore.add(saved)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        let edited = TranscriptSession(
            id: saved.id, createdAt: saved.createdAt, transcript: "saved (edited)", duration: 30,
            model: "whisper-1", languageHint: nil, prompt: nil, pendingTranscription: nil, artifactsDirectoryPath: nil
        )

        harness.appState.currentTranscript = edited

        XCTAssertFalse(harness.appState.currentTranscriptIsPersisted, "an edited draft is not value-equal to the stored copy")
        XCTAssertEqual(viewModel.allSessionEntries.count, 1, "no duplicate row")
        XCTAssertEqual(viewModel.allSessions.first?.transcript, "saved (edited)")
        // The detail pane must show the EDITED draft, not the store's stale copy;
        // only the resolveSession shortcut produces that.
        harness.appState.selectedTranscriptID = saved.id
        XCTAssertEqual(viewModel.selectedSession?.transcript, "saved (edited)")
    }

    // MARK: - selectedSession (date-irrelevant: .allSessions so midnight cannot matter)

    func testSelectedSessionFallsBackToFirstFilteredEntryWhenNothingIsSelected() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let newest = makeSession(createdAt: daysAgo(1), transcript: "newest")
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(2), transcript: "older"))
        try harness.transcriptStore.add(newest)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = nil

        XCTAssertEqual(viewModel.selectedSession?.id, newest.id)
    }

    func testSelectedSessionHonoursASelectionInsideTheFilteredSet() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let older = makeSession(createdAt: daysAgo(2), transcript: "older")
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "newest"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = older.id

        XCTAssertEqual(viewModel.selectedSession?.id, older.id)
    }

    func testSelectedSessionFallsBackWhenTheSelectionIsFilteredOut() throws {
        // Selected something, then searched it away: the detail pane must show
        // a visible entry, not a phantom. Resolving against ALL sessions instead
        // of the filtered set would keep showing the hidden one.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let apple = makeSession(createdAt: daysAgo(1), transcript: "apple")
        let banana = makeSession(createdAt: daysAgo(2), transcript: "banana")
        try harness.transcriptStore.add(apple)
        try harness.transcriptStore.add(banana)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = apple.id
        viewModel.searchText = "banana"

        XCTAssertEqual(viewModel.filteredEntries.map(\.id), [banana.id], "precondition: search excludes apple")
        XCTAssertEqual(viewModel.selectedSession?.id, banana.id)
    }

    func testSelectedSessionIsNilWhenNothingMatches() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "apple"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        viewModel.searchText = "zzz-no-match"

        XCTAssertTrue(viewModel.filteredEntries.isEmpty)
        XCTAssertNil(viewModel.selectedSession)
        // The sidebar's "no results" message and its "show all" button both hang
        // off this; a pass-through that returned nil would blank them silently.
        XCTAssertEqual(viewModel.emptyState, .noSearchResults)
    }

    // MARK: - syncSelection (writes the same decision back to AppState)

    func testSyncSelectionClearsTheSelectionWhenNothingMatches() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let apple = makeSession(createdAt: daysAgo(1), transcript: "apple")
        try harness.transcriptStore.add(apple)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = apple.id
        viewModel.searchText = "zzz-no-match"

        viewModel.syncSelection()

        XCTAssertNil(harness.appState.selectedTranscriptID)
    }

    func testSyncSelectionKeepsASelectionThatIsStillVisible() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let older = makeSession(createdAt: daysAgo(2), transcript: "older")
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "newest"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = older.id

        viewModel.syncSelection()

        XCTAssertEqual(harness.appState.selectedTranscriptID, older.id, "must not be replaced by the first entry")
    }

    func testSyncSelectionMovesAFilteredOutSelectionToTheFirstVisibleEntryNotTheLast() throws {
        // Three visible matches so that .first, .last, and "any" are all distinguishable.
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let apple = makeSession(createdAt: daysAgo(1), transcript: "apple")
        let b1 = makeSession(createdAt: daysAgo(2), transcript: "banana one")
        let b2 = makeSession(createdAt: daysAgo(3), transcript: "banana two")
        let b3 = makeSession(createdAt: daysAgo(4), transcript: "banana three")
        for s in [apple, b1, b2, b3] { try harness.transcriptStore.add(s) }
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        harness.appState.selectedTranscriptID = apple.id
        viewModel.searchText = "banana"

        viewModel.syncSelection()

        XCTAssertEqual(viewModel.filteredEntries.map(\.id), [b1.id, b2.id, b3.id], "precondition: newest-first")
        XCTAssertEqual(harness.appState.selectedTranscriptID, b1.id)
    }

    // MARK: - openLatestPendingTranscriptionSession (the sidebar's retry banner)

    func testOpenLatestPendingSwitchesFilterClearsSearchAndSelectsThePendingSession() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let pending = makeSession(createdAt: daysAgo(2), transcript: "needs retry", pendingRetry: true)
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "fine"))
        try harness.transcriptStore.add(pending)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .today
        viewModel.searchText = "fine"
        harness.appState.selectedTranscriptID = nil

        viewModel.openLatestPendingTranscriptionSession()

        XCTAssertEqual(viewModel.selectedFilter, .retryNeeded, "must switch to the filter that shows it")
        XCTAssertEqual(viewModel.searchText, "", "a stale search would hide it")
        XCTAssertEqual(harness.appState.selectedTranscriptID, pending.id)
    }

    // MARK: - sortOrder is honoured by the query

    func testSortOrderFlipsTheVisibleOrder() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let older = makeSession(createdAt: daysAgo(3), transcript: "older")
        let newer = makeSession(createdAt: daysAgo(1), transcript: "newer")
        try harness.transcriptStore.add(older)
        try harness.transcriptStore.add(newer)
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions

        viewModel.sortOrder = .newestFirst
        XCTAssertEqual(viewModel.filteredEntries.map(\.id), [newer.id, older.id])
        viewModel.sortOrder = .oldestFirst
        XCTAssertEqual(viewModel.filteredEntries.map(\.id), [older.id, newer.id], "the published sortOrder must reach the query")
    }

    // MARK: - sessionCountSummary

    func testCountSummaryCountsTheFilteredSetNotTheWholeLibrary() throws {
        // Under .today, an old session must not be counted. Counting
        // allSessionEntries instead of filteredEntries would say "2 sessions".
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: Date(), transcript: "today"))
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "old"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .today

        XCTAssertEqual(viewModel.sessionCountSummary, "1 session")
    }

    func testCountSummaryPluralisesSessionsAndRetries() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions

        XCTAssertEqual(viewModel.sessionCountSummary, "0 sessions")
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "one"))
        XCTAssertEqual(viewModel.sessionCountSummary, "1 session")
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(2), transcript: "two", pendingRetry: true))
        XCTAssertEqual(viewModel.sessionCountSummary, "2 sessions • 1 needs retry")
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "three", pendingRetry: true))
        XCTAssertEqual(viewModel.sessionCountSummary, "3 sessions • 2 need retry")
    }

    func testCountSummaryUsesResultsWordingWhenSearching() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "apple pie"))
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(2), transcript: "apple tart"))
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(3), transcript: "banana"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions

        viewModel.searchText = "apple"
        XCTAssertEqual(viewModel.sessionCountSummary, "2 results for “apple”")
        viewModel.searchText = "banana"
        XCTAssertEqual(viewModel.sessionCountSummary, "1 result for “banana”")
    }

    func testCountSummaryTreatsWhitespaceOnlySearchAsNoSearch() throws {
        let harness = AppStateHarness()
        defer { harness.cleanup() }
        try harness.transcriptStore.add(makeSession(createdAt: daysAgo(1), transcript: "one"))
        let viewModel = makeViewModel(harness)
        viewModel.selectedFilter = .allSessions
        viewModel.searchText = "   "

        XCTAssertEqual(viewModel.sessionCountSummary, "1 session")
    }

    // MARK: - Helpers

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    private func makeViewModel(_ harness: AppStateHarness) -> SessionLibraryViewModel {
        SessionLibraryViewModel(appState: harness.appState, transcriptStore: harness.transcriptStore)
    }

    private func makeSession(createdAt: Date, transcript: String, pendingRetry: Bool = false) -> TranscriptSession {
        TranscriptSession(
            id: UUID(),
            createdAt: createdAt,
            transcript: transcript,
            duration: 30,
            model: "whisper-1",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: pendingRetry
                ? PendingTranscription(audioFileName: "recording.m4a", failureReason: .missingAPIKey, preservedAt: createdAt)
                : nil,
            artifactsDirectoryPath: nil
        )
    }
}
