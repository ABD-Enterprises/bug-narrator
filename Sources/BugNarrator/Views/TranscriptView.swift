import AppKit
import SwiftUI

struct TranscriptView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore

    @State private var exportErrorMessage: String?
    @State private var pendingDeletionIDs: Set<UUID> = []
    @State private var showDeletionConfirmation = false
    @State private var searchText = ""
    @State private var sortOrder: SessionLibrarySortOrder = .newestFirst
    @State private var selectedFilter: SessionLibraryDateFilter = .today
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var selectedDetailTab: DetailTab = .rawTranscript
    @State private var hasResolvedInitialFilter = false

    private let exporter = TranscriptExporter()
    private let calendar = Calendar.current

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } content: {
            sessionListColumn
                .navigationSplitViewColumnWidth(min: 360, ideal: 420)
        } detail: {
            detailPane
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    requestDeletion(for: selectedSession.map { Set([$0.id]) } ?? [])
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                .disabled(selectedSession == nil)
            }
        }
        .alert(deletionAlertTitle, isPresented: $showDeletionConfirmation) {
            Button("Delete", role: .destructive) {
                let ids = pendingDeletionIDs
                pendingDeletionIDs.removeAll()
                appState.deleteSessions(withIDs: ids)
            }

            Button("Cancel", role: .cancel) {
                pendingDeletionIDs.removeAll()
            }
        } message: {
            Text(deletionAlertMessage)
        }
        .alert("Export Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            Text(exportErrorMessage ?? "Unknown export failure.")
        }
        .onAppear {
            resolveInitialFilterIfNeeded()
            syncSelection()
        }
        .onChange(of: selectedFilter) { _, _ in
            syncSelection()
        }
        .onChange(of: searchText) { _, _ in
            syncSelection()
        }
        .onChange(of: sortOrder) { _, _ in
            syncSelection()
        }
        .onChange(of: customStartDate) { _, _ in
            selectedFilter = .customRange
            syncSelection()
        }
        .onChange(of: customEndDate) { _, _ in
            selectedFilter = .customRange
            syncSelection()
        }
        .onChange(of: sessionIDSignature) { _, _ in
            resolveInitialFilterIfNeeded()
            syncSelection()
        }
        .onChange(of: appState.selectedTranscriptID) { _, _ in
            selectedDetailTab = .rawTranscript
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Session Library")
                        .font(.title3.weight(.semibold))

                    Text("A durable archive for recorded feedback sessions, summaries, screenshots, and extracted issues.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(SessionLibraryDateFilter.allCases) { filter in
                        filterButton(for: filter)
                    }
                }

                if selectedFilter == .customRange {
                    customRangeSection
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sessionListColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionListHeader

            if let emptyState {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: emptyState.systemImage)
                } description: {
                    Text(emptyState.description)
                } actions: {
                    if emptyState == .noSearchResults {
                        Button("Clear Search") {
                            searchText = ""
                        }
                    } else if selectedFilter != .allSessions {
                        Button("Show All Sessions") {
                            selectedFilter = .allSessions
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectionBinding) {
                    ForEach(filteredEntries) { entry in
                        sessionRow(entry: entry)
                            .tag(Optional(entry.id))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                            .listRowBackground(Color.clear)
                            .contextMenu {
                                Button("Copy Transcript") {
                                    appState.selectedTranscriptID = entry.id
                                    appState.copyDisplayedTranscript()
                                }

                                Divider()

                                Button("Delete Session", role: .destructive) {
                                    requestDeletion(for: Set([entry.id]))
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var detailPane: some View {
        Group {
            if let selectedSession {
                transcriptDetail(for: selectedSession)
            } else if allSessions.isEmpty, appState.needsAPIKeySetup {
                ContentUnavailableView {
                    Label("OpenAI API Key Required", systemImage: "key.horizontal")
                } description: {
                    Text("You can record without an OpenAI API key, but you need one in Settings before a session can be transcribed into the library.")
                } actions: {
                    Button("Open Settings") {
                        appState.openSettings()
                    }
                }
            } else if let emptyState {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: emptyState.systemImage)
                } description: {
                    Text(emptyState.description)
                }
            } else {
                ContentUnavailableView(
                    "Select a Session",
                    systemImage: "sidebar.right",
                    description: Text("Choose a session from the list to inspect the full transcript, markers, screenshots, and extracted issues.")
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var sessionListHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedFilter.rawValue)
                        .font(.title3.weight(.semibold))

                    Text(sessionCountSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Sort", selection: $sortOrder) {
                    ForEach(SessionLibrarySortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
            }

            HStack(spacing: 10) {
                Label {
                    TextField("Search title, transcript, or summary", text: $searchText)
                        .textFieldStyle(.plain)
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(role: .destructive) {
                    requestDeletion(for: selectedSession.map { Set([$0.id]) } ?? [])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedSession == nil)
            }
        }
    }

    private var customRangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Date Range")
                .font(.subheadline.weight(.semibold))

            DatePicker("Start", selection: $customStartDate, displayedComponents: .date)
                .datePickerStyle(.field)

            DatePicker("End", selection: $customEndDate, displayedComponents: .date)
                .datePickerStyle(.field)

            Text("\(count(for: .customRange)) sessions in range")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func filterButton(for filter: SessionLibraryDateFilter) -> some View {
        Button {
            selectedFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: filter.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(selectedFilter == filter ? Color.accentColor : .secondary)

                Text(filter.rawValue)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(count(for: filter))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedFilter == filter ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        selectedFilter == filter
                            ? Color.accentColor.opacity(0.12)
                            : Color(nsColor: .separatorColor).opacity(0.18),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
                .background(
                    selectedFilter == filter
                    ? Color.accentColor.opacity(0.09)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { appState.selectedTranscriptID },
            set: { appState.selectedTranscriptID = $0 }
        )
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    exportErrorMessage = nil
                }
            }
        )
    }

    private var allSessions: [TranscriptSession] {
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

    private var allSessionEntries: [SessionLibraryEntry] {
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

    private var query: SessionLibraryQuery {
        SessionLibraryQuery(
            filter: selectedFilter,
            customDateRange: SessionLibraryDateRange(startDate: customStartDate, endDate: customEndDate),
            searchText: searchText,
            sortOrder: sortOrder
        )
    }

    private var librarySnapshot: SessionLibrarySnapshot<SessionLibraryEntry> {
        SessionLibrary.snapshot(
            from: allSessionEntries,
            query: query,
            calendar: calendar
        )
    }

    private var filteredEntries: [SessionLibraryEntry] {
        librarySnapshot.filteredItems
    }

    private var selectedSession: TranscriptSession? {
        guard let selectedTranscriptID = appState.selectedTranscriptID else {
            return filteredEntries.first.flatMap(resolveSession(for:))
        }

        guard let selectedEntry = filteredEntries.first(where: { $0.id == selectedTranscriptID }) else {
            return filteredEntries.first.flatMap(resolveSession(for:))
        }

        return resolveSession(for: selectedEntry)
    }

    private var emptyState: SessionLibraryEmptyState? {
        librarySnapshot.emptyState
    }

    private var sessionCountSummary: String {
        let count = filteredEntries.count
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return count == 1 ? "1 session" : "\(count) sessions"
        }

        return count == 1 ? "1 result for “\(searchText)”" : "\(count) results for “\(searchText)”"
    }

    private var sessionIDSignature: String {
        allSessionEntries.map(\.id.uuidString).joined(separator: "|")
    }

    private var deletionAlertTitle: String {
        pendingDeletionIDs.count == 1 ? "Delete Session?" : "Delete \(pendingDeletionIDs.count) Sessions?"
    }

    private var deletionAlertMessage: String {
        let targetSessions = allSessions.filter { pendingDeletionIDs.contains($0.id) }
        let screenshotCount = targetSessions.reduce(0) { partialResult, session in
            partialResult + session.screenshotCount
        }

        if screenshotCount > 0 {
            return "This permanently removes the selected session and deletes \(screenshotCount) locally stored screenshot\(screenshotCount == 1 ? "" : "s"). Exported files outside BugNarrator are not removed."
        }

        return "This permanently removes the selected session from BugNarrator."
    }

    private func count(for filter: SessionLibraryDateFilter) -> Int {
        librarySnapshot.counts[filter] ?? 0
    }

    private func resolveInitialFilterIfNeeded() {
        guard !hasResolvedInitialFilter else {
            return
        }

        hasResolvedInitialFilter = true
        if count(for: .today) == 0, !allSessionEntries.isEmpty {
            selectedFilter = .allSessions
        }
    }

    private func syncSelection() {
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

    private func requestDeletion(for ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        pendingDeletionIDs = ids
        showDeletionConfirmation = true
    }

    private func sessionRow(entry: SessionLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isUnsaved(entry.id) {
                    Text("Unsaved")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.14), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                metricChip(systemImage: "clock", title: ElapsedTimeFormatter.string(from: entry.duration))

                if entry.markerCount > 0 {
                    metricChip(systemImage: "mappin.and.ellipse", title: "\(entry.markerCount)")
                }

                if entry.screenshotCount > 0 {
                    metricChip(systemImage: "photo", title: "\(entry.screenshotCount)")
                }

                if entry.issueCount > 0 {
                    metricChip(systemImage: "checklist", title: "\(entry.issueCount)")
                }

                Spacer()
            }

            Text(entry.preview)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !entry.summaryText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(entry.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func metricChip(systemImage: String, title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.45), in: Capsule())
    }

    private func isUnsaved(_ sessionID: UUID) -> Bool {
        appState.currentTranscript?.id == sessionID && !appState.currentTranscriptIsPersisted
    }

    private func transcriptDetail(for session: TranscriptSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerSection(session)
                actionSection(session)
                tabPicker(for: session)
                detailContent(for: session)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headerSection(_ session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(.title2.weight(.semibold))

                    Text("Review the transcript, refine extracted issues, then export only what you want to keep or share.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        metricChip(systemImage: "calendar", title: session.createdAt.formatted(date: .abbreviated, time: .shortened))
                        metricChip(systemImage: "clock", title: ElapsedTimeFormatter.string(from: session.duration))
                        metricChip(systemImage: "waveform", title: session.model)
                    }
                }

                Spacer()

                if appState.status.phase == .recording {
                    Button("Open Recording Controls") {
                        appState.openRecordingControls()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack(spacing: 8) {
                if session.markerCount > 0 {
                    metricChip(systemImage: "mappin.and.ellipse", title: "\(session.markerCount) markers")
                }

                if session.screenshotCount > 0 {
                    metricChip(systemImage: "photo", title: "\(session.screenshotCount) screenshots")
                }

                if session.issueCount > 0 {
                    metricChip(systemImage: "checklist", title: "\(session.issueCount) issues")
                }
            }

            if isUnsaved(session.id) {
                HStack {
                    Text("Auto-save is off. This transcript is only in memory until you quit the app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save to History") {
                        appState.saveCurrentTranscriptToHistory()
                    }
                }
            }

            if appState.status.phase == .recording {
                liveReviewControls
            }
        }
    }

    private func actionSection(_ session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Actions")
                .font(.headline)

            HStack(spacing: 10) {
                Button("Copy Transcript") {
                    appState.selectedTranscriptID = session.id
                    appState.copyDisplayedTranscript()
                }

                Button(appState.isExtractingIssues(for: session) ? "Extracting Issues..." : "Extract Issues") {
                    appState.selectedTranscriptID = session.id
                    Task {
                        await appState.extractIssuesForDisplayedTranscript()
                    }
                }
                .disabled(appState.isExtractingIssues(for: session))

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Export TXT") {
                    export(session: session, format: .text)
                }

                Button("Export Markdown") {
                    export(session: session, format: .markdown)
                }

                Button("Export Session Bundle") {
                    exportBundle(session: session)
                }

                Button("Export Debug Bundle") {
                    appState.selectedTranscriptID = session.id
                    Task {
                        await appState.exportDebugBundle()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tabPicker(for session: TranscriptSession) -> some View {
        Picker("Session Detail", selection: $selectedDetailTab) {
            ForEach(detailTabs(for: session)) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(10)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var liveReviewControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Label("Recording is active", systemImage: "record.circle.fill")
                    .foregroundStyle(.red)

                Text(appState.elapsedTimeString)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)

                Spacer()
            }

            Text("Markers and screenshots are available from the recording controls window and global hotkeys.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func detailContent(for session: TranscriptSession) -> some View {
        switch selectedDetailTab {
        case .rawTranscript:
            rawTranscriptSection(session)
        case .reviewSummary:
            reviewSummarySection(session)
        case .markers:
            markersSection(session)
        case .screenshots:
            screenshotsSection(session)
        case .extractedIssues:
            extractedIssuesSection(session)
        }
    }

    private func reviewSummarySection(_ session: TranscriptSession) -> some View {
        detailCard(title: "Review Summary", subtitle: "A concise readout of the issues and themes BugNarrator extracted from this feedback session.") {
            if let extraction = session.issueExtraction, !extraction.summary.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(extraction.summary)
                        .textSelection(.enabled)

                    Text(extraction.guidanceNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if !session.summaryText.isEmpty {
                Text(session.summaryText)
                    .textSelection(.enabled)
            } else {
                Text("No review summary is available for this session yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rawTranscriptSection(_ session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            detailCard(title: "Raw Transcript", subtitle: "The full transcript stays separate from summaries and extracted issues.") {
                Text(session.transcript)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !session.sections.isEmpty {
                transcriptSections(session)
            }
        }
    }

    private func markersSection(_ session: TranscriptSession) -> some View {
        detailCard(title: "Markers", subtitle: "Markers keep important moments aligned with the session timeline.") {
            if session.markers.isEmpty {
                Text("No markers were inserted for this session.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.markers) { marker in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(marker.title)
                                .font(.body.weight(.semibold))

                            Spacer()

                            Text(marker.timeLabel)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let note = marker.note, !note.isEmpty {
                            Text(note)
                                .foregroundStyle(.secondary)
                        }

                        if let screenshotID = marker.screenshotID,
                           let screenshot = session.screenshot(with: screenshotID) {
                            Button("Open \(screenshot.fileName)") {
                                appState.openScreenshot(screenshot)
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                }
            }
        }
    }

    private func screenshotsSection(_ session: TranscriptSession) -> some View {
        detailCard(title: "Screenshots", subtitle: "Visual evidence stays tied to the session timeline and related markers.") {
            if session.screenshots.isEmpty {
                Text("No screenshots were captured for this session.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(session.screenshots) { screenshot in
                        VStack(alignment: .leading, spacing: 10) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.quaternary.opacity(0.5))
                                .frame(height: 120)
                                .overlay {
                                    VStack(spacing: 6) {
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                        Text(screenshot.fileName)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 8)
                                    }
                                }

                            Text(screenshot.fileName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)

                            HStack {
                                Text(screenshot.timeLabel)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let associatedMarkerID = screenshot.associatedMarkerID,
                                   let marker = session.marker(with: associatedMarkerID) {
                                    Text(marker.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Button("Open Screenshot") {
                                appState.openScreenshot(screenshot)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private func extractedIssuesSection(_ session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let extraction = session.issueExtraction {
                detailCard(title: "Extracted Issues", subtitle: "Reviewable draft issues with transcript evidence and optional screenshot links.") {
                    VStack(alignment: .leading, spacing: 14) {
                        if !extraction.guidanceNote.isEmpty {
                            Text(extraction.guidanceNote)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            Button("Select All") {
                                appState.setAllIssuesSelected(true, in: session.id)
                            }

                            Button("Select None") {
                                appState.setAllIssuesSelected(false, in: session.id)
                            }

                            Spacer()

                            Button(appState.isExporting(to: .github) ? "Exporting to GitHub..." : "Export to GitHub") {
                                Task {
                                    await appState.exportSelectedIssues(from: session, to: .github)
                                }
                            }
                            .disabled(!appState.canExportIssues(from: session, to: .github) || appState.isExporting(to: .github))

                            Button(appState.isExporting(to: .jira) ? "Exporting to Jira..." : "Export to Jira") {
                                Task {
                                    await appState.exportSelectedIssues(from: session, to: .jira)
                                }
                            }
                            .disabled(!appState.canExportIssues(from: session, to: .jira) || appState.isExporting(to: .jira))
                        }

                        if extraction.issues.isEmpty {
                            Text("No reviewable issues were extracted from this transcript.")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(extraction.issues) { issue in
                                    issueCard(issue: issue, session: session)
                                }
                            }
                        }
                    }
                }
            } else {
                detailCard(title: "Extracted Issues", subtitle: "Turn this transcript into reviewable draft bugs, UX issues, enhancements, and follow-ups.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Run issue extraction to turn this transcript into reviewable draft bugs, UX issues, enhancements, and follow-ups.")
                            .foregroundStyle(.secondary)

                        Button(appState.isExtractingIssues(for: session) ? "Extracting Issues..." : "Extract Issues") {
                            appState.selectedTranscriptID = session.id
                            Task {
                                await appState.extractIssuesForDisplayedTranscript()
                            }
                        }
                        .disabled(appState.isExtractingIssues(for: session))
                    }
                }
            }
        }
    }

    private func issueCard(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { extractedIssue(sessionID: session.id, issueID: issue.id)?.isSelectedForExport ?? issue.isSelectedForExport },
                        set: { newValue in
                            appState.setIssueSelection(newValue, issueID: issue.id, in: session.id)
                        }
                    )
                )
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 10) {
                    TextField(
                        "Issue title",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.title, fallback: issue.title)
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 12) {
                        Picker(
                            "Category",
                            selection: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.category, fallback: issue.category)
                        ) {
                            ForEach(ExtractedIssueCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(.menu)

                        Toggle(
                            "Needs Review",
                            isOn: issueBinding(
                                sessionID: session.id,
                                issueID: issue.id,
                                keyPath: \.requiresReview,
                                fallback: issue.requiresReview
                            )
                        )
                        .toggleStyle(.switch)

                        Spacer()
                    }

                    HStack(spacing: 12) {
                        if let timestampLabel = extractedIssue(sessionID: session.id, issueID: issue.id)?.timestampLabel ?? issue.timestampLabel {
                            Label(timestampLabel, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let sectionTitle = extractedIssue(sessionID: session.id, issueID: issue.id)?.sectionTitle ?? issue.sectionTitle,
                           !sectionTitle.isEmpty {
                            Label(sectionTitle, systemImage: "text.quote")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let confidenceLabel = extractedIssue(sessionID: session.id, issueID: issue.id)?.confidenceLabel ?? issue.confidenceLabel {
                            Label(confidenceLabel, systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    fieldEditor(
                        title: "Summary",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.summary, fallback: issue.summary),
                        minHeight: 84
                    )

                    fieldEditor(
                        title: "Evidence",
                        text: issueBinding(
                            sessionID: session.id,
                            issueID: issue.id,
                            keyPath: \.evidenceExcerpt,
                            fallback: issue.evidenceExcerpt
                        ),
                        minHeight: 92
                    )

                    let relatedScreenshots = (extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue).relatedScreenshotIDs
                        .compactMap(session.screenshot(with:))

                    if !relatedScreenshots.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Related Screenshots")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)

                            ForEach(relatedScreenshots) { screenshot in
                                Button(screenshot.fileName) {
                                    appState.openScreenshot(screenshot)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func transcriptSections(_ session: TranscriptSession) -> some View {
        detailCard(title: "Transcript Sections", subtitle: "Markers and screenshots split the transcript into review moments.") {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(session.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(section.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(section.timeRangeLabel)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if !section.screenshotIDs.isEmpty {
                            HStack(spacing: 8) {
                                Text("Screenshots:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ForEach(section.screenshotIDs, id: \.self) { screenshotID in
                                    if let screenshot = session.screenshot(with: screenshotID) {
                                        Button(screenshot.fileName) {
                                            appState.openScreenshot(screenshot)
                                        }
                                        .buttonStyle(.link)
                                    }
                                }
                            }
                        }

                        Text(section.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func detailCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func resolveSession(for entry: SessionLibraryEntry) -> TranscriptSession? {
        if appState.currentTranscript?.id == entry.id {
            return appState.currentTranscript
        }

        return transcriptStore.session(with: entry.id)
    }

    @ViewBuilder
    private func fieldEditor(title: String, text: Binding<String>, minHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: minHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
        }
    }

    private func export(session: TranscriptSession, format: TranscriptExportFormat) {
        do {
            try exporter.export(session: session, as: format)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportBundle(session: TranscriptSession) {
        do {
            try exporter.exportBundle(session: session)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func extractedIssue(sessionID: UUID, issueID: UUID) -> ExtractedIssue? {
        let sourceSession = liveSession(with: sessionID)
        return sourceSession?.issueExtraction?.issues.first(where: { $0.id == issueID })
    }

    private func liveSession(with sessionID: UUID) -> TranscriptSession? {
        if appState.currentTranscript?.id == sessionID {
            return appState.currentTranscript
        }

        return transcriptStore.session(with: sessionID)
    }

    private func issueBinding<Value>(
        sessionID: UUID,
        issueID: UUID,
        keyPath: WritableKeyPath<ExtractedIssue, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                extractedIssue(sessionID: sessionID, issueID: issueID)?[keyPath: keyPath] ?? fallback
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID) else {
                    return
                }

                updatedIssue[keyPath: keyPath] = newValue
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func detailTabs(for session: TranscriptSession) -> [DetailTab] {
        var tabs: [DetailTab] = [.rawTranscript]

        if !session.summaryText.isEmpty || session.issueExtraction != nil {
            tabs.append(.reviewSummary)
        }

        tabs.append(contentsOf: [.markers, .screenshots, .extractedIssues])
        return tabs
    }
}

private enum DetailTab: Identifiable {
    case rawTranscript
    case reviewSummary
    case markers
    case screenshots
    case extractedIssues

    var id: String { title }

    var title: String {
        switch self {
        case .rawTranscript:
            return "Raw Transcript"
        case .reviewSummary:
            return "Review Summary"
        case .markers:
            return "Markers"
        case .screenshots:
            return "Screenshots"
        case .extractedIssues:
            return "Extracted Issues"
        }
    }
}
