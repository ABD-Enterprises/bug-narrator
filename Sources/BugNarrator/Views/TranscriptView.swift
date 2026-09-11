import AppKit
import SwiftUI

struct TranscriptView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var recordingTimer: RecordingTimerViewModel
    @ObservedObject var transcriptStore: TranscriptStore

    @StateObject private var libraryVM: SessionLibraryViewModel

    @State private var exportErrorMessage: String?
    @State private var pendingDeletionIDs: Set<UUID> = []
    @State private var showDeletionConfirmation = false

    private let exporter = TranscriptExporter()

    init(
        appState: AppState,
        recordingTimer: RecordingTimerViewModel,
        transcriptStore: TranscriptStore
    ) {
        self.appState = appState
        self.recordingTimer = recordingTimer
        self.transcriptStore = transcriptStore
        _libraryVM = StateObject(
            wrappedValue: SessionLibraryViewModel(
                appState: appState,
                transcriptStore: transcriptStore
            )
        )
    }

    private var sidebarView: SessionListSidebar {
        SessionListSidebar(
            appState: appState,
            transcriptStore: transcriptStore,
            viewModel: libraryVM,
            requestDeletion: { requestDeletion(for: $0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebarView.sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 260)
        } content: {
            sidebarView.sessionListColumn
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 420)
        } detail: {
            detailPane
                .navigationSplitViewColumnWidth(min: 360, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    requestDeletion(for: libraryVM.selectedSession.map { Set([$0.id]) } ?? [])
                } label: {
                    Label("Delete Session", systemImage: "trash")
                }
                .disabled(libraryVM.selectedSession == nil)
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
        .sheet(item: exportReviewBinding) { review in
            exportReviewSheet(review)
        }
        .onAppear {
            libraryVM.resolveInitialFilterIfNeeded()
            libraryVM.syncSelection()
            Task {
                await appState.refreshExportHistory()
            }
        }
        .onChange(of: libraryVM.selectedFilter) { _, _ in
            libraryVM.syncSelection()
        }
        .onChange(of: libraryVM.searchText) { _, _ in
            libraryVM.syncSelection()
        }
        .onChange(of: libraryVM.sortOrder) { _, _ in
            libraryVM.syncSelection()
        }
        .onChange(of: libraryVM.customStartDate) { _, _ in
            libraryVM.selectedFilter = .customRange
            libraryVM.syncSelection()
        }
        .onChange(of: libraryVM.customEndDate) { _, _ in
            libraryVM.selectedFilter = .customRange
            libraryVM.syncSelection()
        }
        .onChange(of: libraryVM.sessionIDSignature) { _, _ in
            libraryVM.resolveInitialFilterIfNeeded()
            libraryVM.syncSelection()
        }
    }



    private var detailPane: some View {
        Group {
            if let selectedSession = libraryVM.selectedSession {
                transcriptDetail(for: selectedSession)
            } else if libraryVM.allSessions.isEmpty, appState.needsAPIKeySetup {
                ContentUnavailableView {
                    Label(emptyLibrarySetupTitle, systemImage: emptyLibrarySetupSymbol)
                } description: {
                    Text(emptyLibrarySetupDescription)
                } actions: {
                    Button("Open Settings") {
                        appState.openSettings()
                    }
                }
            } else if libraryVM.allSessions.isEmpty {
                ContentUnavailableView {
                    Label("No sessions yet", systemImage: "waveform")
                } description: {
                    Text("Open the recording controls to capture your first BugNarrator session.")
                } actions: {
                    Button("Open Recording Controls") {
                        appState.openRecordingControls()
                    }
                }
            } else if let emptyState = libraryVM.emptyState {
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

    private var exportReviewBinding: Binding<IssueExportReview?> {
        Binding(
            get: { appState.pendingExportReview },
            set: { newValue in
                if newValue == nil {
                    appState.cancelPendingExportReview()
                }
            }
        )
    }










    private var deletionAlertTitle: String {
        pendingDeletionIDs.count == 1 ? "Delete Session?" : "Delete \(pendingDeletionIDs.count) Sessions?"
    }

    private var deletionAlertMessage: String {
        let targetSessions = libraryVM.allSessions.filter { pendingDeletionIDs.contains($0.id) }
        let screenshotCount = targetSessions.reduce(0) { partialResult, session in
            partialResult + session.screenshotCount
        }

        if screenshotCount > 0 {
            return "This permanently removes the selected session and deletes \(screenshotCount) locally stored screenshot\(screenshotCount == 1 ? "" : "s"). Exported files outside BugNarrator are not removed."
        }

        return "This permanently removes the selected session from BugNarrator."
    }




    private func requestDeletion(for ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }

        pendingDeletionIDs = ids
        showDeletionConfirmation = true
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
            .accessibilityLabel("Session detail")
        }
    }

    private func reviewWorkspace(for session: TranscriptSession, availableWidth: CGFloat) -> some View {
        ReviewWorkspaceShell(
            session: session,
            availableWidth: availableWidth,
            appState: appState,
            recordingTimer: recordingTimer,
            defaultRetryRecoveryMessage: defaultRetryRecoveryMessage,
            extractIssuesButton: { extractIssuesButton(for: session) },
            copyTranscriptButton: { copyTranscriptButton(for: session) },
            exportMenu: { exportMenu(session: session) },
            reviewSummarySection: { reviewSummarySection(session) },
            extractedIssuesSection: {
                IssueReviewWorkspaceView(
                    appState: appState,
                    transcriptStore: transcriptStore,
                    session: session,
                    availableWidth: availableWidth
                )
            },
            screenshotsSection: { screenshotsSection(session, availableWidth: availableWidth) }
        )
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

    private func export(session: TranscriptSession, format: TranscriptExportFormat) {
        do {
            if let exportedURL = try exporter.export(session: session, as: format) {
                appState.showRevealInFinderToast("Transcript exported", revealing: exportedURL)
            }
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportBundle(session: TranscriptSession) {
        do {
            if let bundleURL = try exporter.exportBundle(session: session) {
                appState.showRevealInFinderToast("Session bundle exported", revealing: bundleURL)
            }
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private var defaultRetryRecoveryMessage: String {
        let provider = appState.settingsStore.aiProvider
        if provider.requiresAPIKey {
            return "Retry transcription after restoring your \(provider.displayName) API key."
        }
        return "Retry transcription after restoring the \(provider.displayName) setup."
    }

    private var emptyLibrarySetupTitle: String {
        appState.settingsStore.aiProvider.requiresAPIKey
            ? "\(appState.settingsStore.aiProvider.displayName) API Key Required"
            : "\(appState.settingsStore.aiProvider.displayName) Setup Required"
    }

    private var emptyLibrarySetupDescription: String {
        RecordingSetupCopy.emptyLibraryDescription(for: appState.settingsStore.aiProvider)
    }

    private var emptyLibrarySetupSymbol: String {
        appState.settingsStore.aiProvider.requiresAPIKey ? "key.horizontal" : "server.rack"
    }

}
