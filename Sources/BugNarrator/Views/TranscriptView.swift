import AppKit
import SwiftUI

func normalizedOptionalReproductionStepText(_ value: String) -> String? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

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
    @State private var hasResolvedInitialFilter = false

    private let exporter = TranscriptExporter()
    private let calendar = Calendar.current

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 260)
        } content: {
            sessionListColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            detailPane
                .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
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
            pendingTranscriptionBanner

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
                    description: Text("Choose a session from the list to inspect the transcript timeline, screenshots, extracted issues, and summary.")
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

                sortMenu
            }

            HStack(spacing: 10) {
                Label {
                    TextField("Search title, transcript, or summary", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search sessions")
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
                    .accessibilityLabel("Clear search")
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

    @ViewBuilder
    private var pendingTranscriptionBanner: some View {
        if transcriptStore.pendingTranscriptionSessionCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label(pendingTranscriptionBannerTitle, systemImage: "arrow.clockwise.circle")
                    .font(.subheadline.weight(.semibold))

                Text("These sessions were recorded successfully and kept in the library because transcription could not finish. Open the latest one to retry after fixing your OpenAI API key.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Open Latest Retry Needed Session") {
                        openLatestPendingTranscriptionSession()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if !appState.settingsStore.hasAPIKey {
                        Button("Open Settings") {
                            appState.openSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var sortMenu: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text("Sort")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(SessionLibrarySortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        if order == sortOrder {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Text(order.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(sortOrder.rawValue)
                        .lineLimit(1)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Sort sessions")
            .accessibilityValue(sortOrder.rawValue)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.rawValue)
        .accessibilityValue("\(count(for: filter)) sessions")
        .accessibilityHint(selectedFilter == filter ? "Current session filter." : "Filters the session list.")
        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
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
        if count(for: .today) == 0, count(for: .retryNeeded) > 0 {
            selectedFilter = .retryNeeded
        } else if count(for: .today) == 0, !allSessionEntries.isEmpty {
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

    private var pendingTranscriptionBannerTitle: String {
        let count = transcriptStore.pendingTranscriptionSessionCount
        return count == 1
            ? "1 session needs transcription retry"
            : "\(count) sessions need transcription retry"
    }

    private func openLatestPendingTranscriptionSession() {
        selectedFilter = .retryNeeded
        searchText = ""
        appState.selectedTranscriptID = transcriptStore.latestPendingTranscriptionSession?.id
        syncSelection()
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

                HStack(spacing: 6) {
                    if entry.isPendingTranscription {
                        Text("Retry Needed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.yellow.opacity(0.16), in: Capsule())
                    }

                    if isUnsaved(entry.id) {
                        Text("Unsaved")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.orange.opacity(0.14), in: Capsule())
                    }
                }
            }

            HStack(spacing: 8) {
                metricChip(systemImage: "clock", title: ElapsedTimeFormatter.string(from: entry.duration))

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue(sessionRowAccessibilitySummary(for: entry))
        .accessibilityHint("Selects this session and updates the detail pane.")
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
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    reviewWorkspace(for: session, availableWidth: proxy.size.width)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func reviewWorkspace(for session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            workspaceHeader(session, availableWidth: availableWidth)
            dividerSection
            workspaceActions(session, availableWidth: availableWidth)
            dividerSection
            workspaceSections(for: session, availableWidth: availableWidth)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func workspaceHeader(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title)
                .font(availableWidth < 360 ? .title3.weight(.semibold) : .title2.weight(.semibold))

            Text(sessionMetadataLine(for: session))
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if session.requiresTranscriptionRetry {
                HStack(alignment: .center, spacing: 10) {
                    Label(
                        session.transcriptionRecoveryMessage ?? "Retry transcription after restoring your OpenAI API key.",
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if appState.settingsStore.hasAPIKey {
                        Button("Retry Transcription") {
                            Task {
                                await appState.retryPendingTranscription(for: session.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button("Open Settings") {
                            appState.openSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else if isUnsaved(session.id) {
                HStack(spacing: 10) {
                    Label("Only stored in memory until you save it.", systemImage: "tray")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Save to History") {
                        appState.saveCurrentTranscriptToHistory()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if appState.status.phase == .recording {
                HStack(spacing: 10) {
                    Label("Recording is active", systemImage: "record.circle.fill")
                        .foregroundStyle(.red)

                    Text(appState.elapsedTimeString)
                        .font(.system(.footnote, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Open Recording Controls") {
                        appState.openRecordingControls()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func sessionMetadataLine(for session: TranscriptSession) -> String {
        "\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) • \(ElapsedTimeFormatter.string(from: session.duration)) • \(session.model)"
    }

    private var dividerSection: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.45))
    }

    private func workspaceActions(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        Group {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        extractIssuesButton(for: session)
                        copyTranscriptButton(for: session)
                    }

                    exportMenu(session: session)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    extractIssuesButton(for: session)
                    copyTranscriptButton(for: session)

                    Spacer(minLength: 12)

                    exportMenu(session: session)
                }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func workspaceSections(for session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            reviewSectionCard("Review Summary") {
                reviewSummarySection(session)
            }

            reviewSectionCard("Extracted Issues") {
                extractedIssuesSection(session, availableWidth: availableWidth)
            }

            reviewSectionCard("Screenshots") {
                screenshotsSection(session, availableWidth: availableWidth)
            }

            reviewSectionCard("Transcript Timeline") {
                rawTranscriptSection(session, availableWidth: availableWidth)
            }
        }
    }

    private func reviewSectionCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func reviewSummarySection(_ session: TranscriptSession) -> some View {
        if let extraction = session.issueExtraction {
            let groupedIssues = ReviewWorkspace.summaryGroups(for: extraction.issues)

            VStack(alignment: .leading, spacing: 18) {
                if !groupedIssues.isEmpty {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedIssues, id: \.category) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(.body.weight(.semibold))

                                ForEach(group.issues) { issue in
                                    Text("– \(issue.title)")
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                if groupedIssues.isEmpty || extraction.issues.isEmpty {
                    if !extraction.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(extraction.summary)
                            .textSelection(.enabled)
                    }
                }
            }
        } else if !session.summaryText.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(session.summaryText)
                    .textSelection(.enabled)
            }
        } else {
            emptyDetailState(
                title: "No review summary yet",
                message: "Generate or extract issues for this session to build a concise summary."
            )
        }
    }

    private func rawTranscriptSection(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        let entries = ReviewWorkspace.timelineEntries(for: session)

        return LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(entries) { entry in
                transcriptTimelineRow(entry, session: session, availableWidth: availableWidth)
            }
        }
    }

    private func transcriptTimelineRow(_ entry: ReviewWorkspaceTimelineEntry, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        Group {
            if availableWidth < 360 {
                VStack(alignment: .leading, spacing: 10) {
                    timelineTimestampLabel(entry.timeLabel)
                    timelineEntryContent(entry, session: session)
                }
            } else {
                HStack(alignment: .top, spacing: 14) {
                    timelineTimestampLabel(entry.timeLabel)
                        .frame(width: 56, alignment: .leading)

                    timelineEntryContent(entry, session: session)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func timelineTimestampLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(.body, design: .monospaced))
            .fontWeight(.semibold)
            .foregroundStyle(.pink)
    }

    @ViewBuilder
    private func timelineEntryContent(_ entry: ReviewWorkspaceTimelineEntry, session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.kind {
            case .transcript:
                if let title = entry.title, !title.isEmpty, title != "Full Session" {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(entry.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

            case .marker:
                Text("Timeline marker")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(.body.weight(.semibold))

            case .screenshot:
                Text("Screenshot marker")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(.body.weight(.semibold))

                if let screenshotID = entry.screenshotID,
                   let screenshot = session.screenshot(with: screenshotID) {
                    Button("Open Screenshot") {
                        appState.openScreenshot(screenshot)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(screenshotActionLabel(for: screenshot, index: nil, action: "Open"))
                }
            }

            if let secondaryText = entry.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private func screenshotsSection(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        if session.screenshots.isEmpty {
            emptyDetailState(
                title: "No screenshots yet",
                message: "Capture a screenshot during recording to review it here."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(session.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                    screenshotTimelineRow(screenshot, index: index, session: session, availableWidth: availableWidth)
                }
            }
        }
    }

    private func screenshotTimelineRow(_ screenshot: SessionScreenshot, index: Int, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        let linkedMarker = screenshot.associatedMarkerID.flatMap { session.marker(with: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 10) {
                    screenshotMetadataBlock(screenshot, index: index, linkedMarker: linkedMarker)

                    Button("Open Screenshot") {
                        appState.openScreenshot(screenshot)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    screenshotMetadataBlock(screenshot, index: index, linkedMarker: linkedMarker)

                    Spacer()

                    Button("Open Screenshot") {
                        appState.openScreenshot(screenshot)
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
                }
            }

            Button {
                appState.openScreenshot(screenshot)
            } label: {
                screenshotPreview(screenshot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(screenshotActionLabel(for: screenshot, index: index, action: "Open"))
            .accessibilityHint("Opens the saved screenshot file.")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func screenshotMetadataBlock(_ screenshot: SessionScreenshot, index: Int, linkedMarker: SessionMarker?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Screenshot")
                    .font(.body.weight(.semibold))

                Text("\(index + 1)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 8) {
                metadataChip(label: screenshot.timeLabel, systemImage: "clock")

                if let linkedMarker {
                    metadataChip(label: linkedMarker.title, systemImage: "mappin.and.ellipse")
                }
            }
        }
    }

    private func metadataChip(label: String, systemImage: String) -> some View {
        return Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.32), in: Capsule())
    }

    @ViewBuilder
    private func screenshotPreview(_ screenshot: SessionScreenshot) -> some View {
        if let image = ScreenshotPreviewCache.shared.previewImage(for: screenshot.fileURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 220, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.quaternary.opacity(0.5), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 180)
                .overlay(alignment: .center) {
                    Text("[preview unavailable]")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func extractedIssuesSection(_ session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let extraction = session.issueExtraction {
                VStack(alignment: .leading, spacing: 14) {
                    Text(extraction.guidanceNote.isEmpty ? "Review before exporting." : extraction.guidanceNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if extraction.issues.isEmpty {
                        emptyDetailState(
                            title: "No extracted issues",
                            message: "Issue extraction ran, but it did not return any draft issues for this session."
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(extraction.issues) { issue in
                                issueReviewRow(issue: issue, session: session, availableWidth: availableWidth)
                            }
                        }

                        Divider()
                            .padding(.top, 4)

                        Text(ReviewWorkspace.selectedIssueSummary(for: session))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button(appState.isExporting(to: .github) ? "Exporting to GitHub..." : "Export to GitHub (Experimental)") {
                                Task {
                                    await appState.exportSelectedIssues(from: session, to: .github)
                                }
                            }
                            .disabled(!appState.canExportIssues(from: session, to: .github) || appState.isExporting(to: .github))

                            Button(appState.isExporting(to: .jira) ? "Exporting to Jira..." : "Export to Jira (Experimental)") {
                                Task {
                                    await appState.exportSelectedIssues(from: session, to: .jira)
                                }
                            }
                            .disabled(!appState.canExportIssues(from: session, to: .jira) || appState.isExporting(to: .jira))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            } else {
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

    private func issueReviewRow(issue: ExtractedIssue, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if availableWidth < 420 {
                VStack(alignment: .leading, spacing: 12) {
                    issueSelectionToggle(issue: issue, session: session)
                    issueContent(issue: issue, session: session, availableWidth: availableWidth)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    issueSelectionToggle(issue: issue, session: session)
                    issueContent(issue: issue, session: session, availableWidth: availableWidth)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func emptyDetailState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func extractIssuesButton(for session: TranscriptSession) -> some View {
        Button(appState.isExtractingIssues(for: session) ? "Extracting Issues..." : "Extract Issues") {
            appState.selectedTranscriptID = session.id
            Task {
                await appState.extractIssuesForDisplayedTranscript()
            }
        }
        .disabled(appState.isExtractingIssues(for: session) || session.requiresTranscriptionRetry)
    }

    private func copyTranscriptButton(for session: TranscriptSession) -> some View {
        Button("Copy Transcript") {
            appState.selectedTranscriptID = session.id
            appState.copyDisplayedTranscript()
        }
        .disabled(session.requiresTranscriptionRetry || !session.hasTranscriptContent)
    }

    private func exportMenu(session: TranscriptSession) -> some View {
        Menu("Export") {
            Button("Export TXT") {
                export(session: session, format: .text)
            }

            Button("Export Markdown") {
                export(session: session, format: .markdown)
            }

            Button("Export Session Bundle") {
                exportBundle(session: session)
            }
        }
        .disabled(session.requiresTranscriptionRetry || !session.hasTranscriptContent)
    }

    private func issueSelectionToggle(issue: ExtractedIssue, session: TranscriptSession) -> some View {
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
        .accessibilityLabel("Select issue \(issue.title) for export")
        .accessibilityValue((extractedIssue(sessionID: session.id, issueID: issue.id)?.isSelectedForExport ?? issue.isSelectedForExport) ? "Selected" : "Not selected")
        .accessibilityHint("Controls whether this extracted issue is included in GitHub or Jira export.")
    }

    @ViewBuilder
    private func issueContent(issue: ExtractedIssue, session: TranscriptSession, availableWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if availableWidth < 520 {
                VStack(alignment: .leading, spacing: 8) {
                    issueCategoryPicker(issue: issue, session: session)

                    TextField(
                        "Issue title",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.title, fallback: issue.title)
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Issue title for \(issue.title)")

                    issueReviewBadge(issue: issue, session: session)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    issueCategoryPicker(issue: issue, session: session)

                    Text("—")
                        .foregroundStyle(.secondary)

                    TextField(
                        "Issue title",
                        text: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.title, fallback: issue.title)
                    )
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Issue title for \(issue.title)")

                    Spacer()

                    issueReviewBadge(issue: issue, session: session)
                }
            }

            if let timestampLabel = extractedIssue(sessionID: session.id, issueID: issue.id)?.timestampLabel ?? issue.timestampLabel {
                Text("Timestamp: \(timestampLabel)")
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundStyle(.pink)
            }

            Text("Evidence: \"\((extractedIssue(sessionID: session.id, issueID: issue.id)?.evidenceExcerpt ?? issue.evidenceExcerpt).trimmingCharacters(in: .whitespacesAndNewlines))\"")
                .textSelection(.enabled)

            if let sectionTitle = extractedIssue(sessionID: session.id, issueID: issue.id)?.sectionTitle ?? issue.sectionTitle,
               !sectionTitle.isEmpty {
                Text("Section: \(sectionTitle)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let summaryText = (extractedIssue(sessionID: session.id, issueID: issue.id)?.summary ?? issue.summary).trimmingCharacters(in: .whitespacesAndNewlines)
            if !summaryText.isEmpty && summaryText != (extractedIssue(sessionID: session.id, issueID: issue.id)?.evidenceExcerpt ?? issue.evidenceExcerpt).trimmingCharacters(in: .whitespacesAndNewlines) {
                Text("Summary: \(summaryText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            let liveIssue = extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue
            if !liveIssue.reproductionSteps.isEmpty {
                reproductionStepsSection(issue: liveIssue, session: session)
            }

            let relatedScreenshots = (extractedIssue(sessionID: session.id, issueID: issue.id) ?? issue).relatedScreenshotIDs
                .compactMap(session.screenshot(with:))
            if !relatedScreenshots.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Screenshots:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(relatedScreenshots) { screenshot in
                        Button(screenshot.fileName) {
                            appState.openScreenshot(screenshot)
                        }
                        .buttonStyle(.link)
                        .accessibilityLabel("Open related screenshot \(screenshot.fileName)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reproductionStepsSection(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reproduction Steps")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(issue.reproductionSteps.enumerated()), id: \.element.id) { index, step in
                reproductionStepEditor(
                    step: step,
                    stepIndex: index,
                    issueID: issue.id,
                    session: session
                )
            }
        }
    }

    private func reproductionStepEditor(
        step: IssueReproductionStep,
        stepIndex: Int,
        issueID: UUID,
        session: TranscriptSession
    ) -> some View {
        let liveStep = reproductionStep(sessionID: session.id, issueID: issueID, stepID: step.id) ?? step
        let referencedScreenshot = liveStep.screenshotID.flatMap(session.screenshot(with:))

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Step \(stepIndex + 1)")
                    .font(.body.weight(.semibold))

                if let timestampLabel = liveStep.timestampLabel {
                    metadataChip(label: timestampLabel, systemImage: "clock")
                }

                if let referencedScreenshot {
                    metadataChip(label: referencedScreenshot.fileName, systemImage: "photo")
                }

                Spacer(minLength: 0)
            }

            fieldEditor(
                title: "Action",
                text: reproductionStepInstructionBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    fallback: liveStep.instruction
                ),
                minHeight: 56
            )

            fieldEditor(
                title: "Expected",
                text: reproductionStepOptionalTextBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    keyPath: \.expectedResult,
                    fallback: liveStep.expectedResult
                ),
                minHeight: 44
            )

            fieldEditor(
                title: "Actual",
                text: reproductionStepOptionalTextBinding(
                    sessionID: session.id,
                    issueID: issueID,
                    stepID: step.id,
                    keyPath: \.actualResult,
                    fallback: liveStep.actualResult
                ),
                minHeight: 44
            )

            if let referencedScreenshot {
                Button("Open Referenced Screenshot") {
                    appState.openScreenshot(referencedScreenshot)
                }
                .buttonStyle(.link)
                .accessibilityLabel("Open referenced screenshot \(referencedScreenshot.fileName) for step \(stepIndex + 1)")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func issueCategoryPicker(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        Picker(
            "",
            selection: issueBinding(sessionID: session.id, issueID: issue.id, keyPath: \.category, fallback: issue.category)
        ) {
            ForEach(ExtractedIssueCategory.allCases) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .accessibilityLabel("Issue category for \(issue.title)")
        .accessibilityValue((extractedIssue(sessionID: session.id, issueID: issue.id)?.category ?? issue.category).rawValue)
    }

    @ViewBuilder
    private func issueReviewBadge(issue: ExtractedIssue, session: TranscriptSession) -> some View {
        if extractedIssue(sessionID: session.id, issueID: issue.id)?.requiresReview ?? issue.requiresReview {
            Text("Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.45), in: Capsule())
        }
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

    private func reproductionStep(sessionID: UUID, issueID: UUID, stepID: UUID) -> IssueReproductionStep? {
        extractedIssue(sessionID: sessionID, issueID: issueID)?
            .reproductionSteps
            .first(where: { $0.id == stepID })
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

    private func reproductionStepInstructionBinding(
        sessionID: UUID,
        issueID: UUID,
        stepID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: {
                reproductionStep(sessionID: sessionID, issueID: issueID, stepID: stepID)?.instruction ?? fallback
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID),
                      let stepIndex = updatedIssue.reproductionSteps.firstIndex(where: { $0.id == stepID }) else {
                    return
                }

                updatedIssue.reproductionSteps[stepIndex].instruction = newValue
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func reproductionStepOptionalTextBinding(
        sessionID: UUID,
        issueID: UUID,
        stepID: UUID,
        keyPath: WritableKeyPath<IssueReproductionStep, String?>,
        fallback: String?
    ) -> Binding<String> {
        Binding(
            get: {
                reproductionStep(sessionID: sessionID, issueID: issueID, stepID: stepID)?[keyPath: keyPath] ?? fallback ?? ""
            },
            set: { newValue in
                guard var updatedIssue = extractedIssue(sessionID: sessionID, issueID: issueID),
                      let stepIndex = updatedIssue.reproductionSteps.firstIndex(where: { $0.id == stepID }) else {
                    return
                }

                updatedIssue.reproductionSteps[stepIndex][keyPath: keyPath] = normalizedOptionalReproductionStepText(newValue)
                appState.updateExtractedIssue(updatedIssue, in: sessionID)
            }
        )
    }

    private func sessionRowAccessibilitySummary(for entry: SessionLibraryEntry) -> String {
        var components = [
            entry.createdAt.formatted(date: .abbreviated, time: .shortened),
            "Duration \(ElapsedTimeFormatter.string(from: entry.duration))"
        ]

        if entry.screenshotCount > 0 {
            components.append("\(entry.screenshotCount) screenshot\(entry.screenshotCount == 1 ? "" : "s")")
        }

        if entry.issueCount > 0 {
            components.append("\(entry.issueCount) extracted issue\(entry.issueCount == 1 ? "" : "s")")
        }

        if entry.isPendingTranscription {
            components.append("Retry needed before transcription is complete")
        }

        if isUnsaved(entry.id) {
            components.append("Unsaved")
        }

        let preview = entry.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            components.append(preview)
        }

        return components.joined(separator: ". ")
    }

    private func screenshotActionLabel(for screenshot: SessionScreenshot, index: Int?, action: String) -> String {
        let ordinal = index.map { "Screenshot \($0 + 1)" } ?? "Screenshot"
        return "\(action) \(ordinal) at \(screenshot.timeLabel)"
    }

}
