import AppKit
import SwiftUI

/// The session library sidebar + session-list column extracted from
/// `TranscriptView` (#631, closes #401 slice d).
///
/// Owns no `@State` itself; the filter/search/sort/date-range state lives
/// on `SessionLibraryViewModel` (a `@StateObject` on `TranscriptView`).
/// Deletion state stays on `TranscriptView`; this view calls back via the
/// `requestDeletion` closure. Selection is threaded via
/// `Binding<UUID?>` derived from `appState.selectedTranscriptID`.
///
/// Pixel-preserving: the sidebar layout (filter chip stack, custom date
/// range section, sort menu, session list header, banners) is a byte-
/// verbatim relocation of the pre-#631 code — same column widths,
/// paddings, spacings, corner radii, and backgrounds.
struct SessionListSidebar: View {
    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore
    @ObservedObject var viewModel: SessionLibraryViewModel

    let requestDeletion: (Set<UUID>) -> Void

    /// Left column: session-library brand + filter chips + custom range.
    var sidebar: some View {
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

                if viewModel.selectedFilter == .customRange {
                    customRangeSection
                }

                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityLabel("Session filters")
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Middle column: session-list header + banners + list-or-empty-state.
    var sessionListColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            sessionListHeader
            storageRecoveryBanner
            pendingTranscriptionBanner

            if let emptyState = viewModel.emptyState {
                ContentUnavailableView {
                    Label(emptyState.title, systemImage: emptyState.systemImage)
                } description: {
                    Text(emptyState.description)
                } actions: {
                    if emptyState == .noSearchResults {
                        Button("Clear Search") {
                            viewModel.searchText = ""
                        }
                    } else if viewModel.selectedFilter != .allSessions {
                        Button("Show All Sessions") {
                            viewModel.selectedFilter = .allSessions
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: selectionBinding) {
                    ForEach(viewModel.filteredEntries) { entry in
                        SessionRow(entry: entry, appState: appState, transcriptStore: transcriptStore)
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
                                    requestDeletion(Set([entry.id]))
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel("Session list")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sessionListHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedFilter.rawValue)
                        .font(.title3.weight(.semibold))

                    Text(viewModel.sessionCountSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                sortMenu
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("Search title, transcript, or summary", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search sessions")
                        .accessibilityIdentifier("session-library-search-field")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !viewModel.searchText.isEmpty {
                    Button("Clear") {
                        viewModel.searchText = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("Clear search")
                }

                Button(role: .destructive) {
                    requestDeletion(viewModel.selectedSession.map { Set([$0.id]) } ?? [])
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedSession == nil)
            }
        }
    }

    @ViewBuilder
    private var pendingTranscriptionBanner: some View {
        if transcriptStore.pendingTranscriptionSessionCount > 0 {
            PendingTranscriptionBanner(
                count: transcriptStore.pendingTranscriptionSessionCount,
                requiresProviderSetup: appState.needsAPIKeySetup,
                provider: appState.settingsStore.aiProvider,
                openLatest: viewModel.openLatestPendingTranscriptionSession,
                openSettings: appState.openSettings
            )
        }
    }

    @ViewBuilder
    private var storageRecoveryBanner: some View {
        if let message = appState.storageRecoveryMessage {
            StorageRecoveryBanner(message: message)
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
                        viewModel.sortOrder = order
                    } label: {
                        if order == viewModel.sortOrder {
                            Label(order.rawValue, systemImage: "checkmark")
                        } else {
                            Text(order.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(viewModel.sortOrder.rawValue)
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
            .accessibilityValue(viewModel.sortOrder.rawValue)
        }
    }

    private var customRangeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom Date Range")
                .font(.subheadline.weight(.semibold))

            DatePicker("Start", selection: $viewModel.customStartDate, displayedComponents: .date)
                .datePickerStyle(.field)

            DatePicker("End", selection: $viewModel.customEndDate, displayedComponents: .date)
                .datePickerStyle(.field)

            Text("\(viewModel.count(for: .customRange)) sessions in range")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func filterButton(for filter: SessionLibraryDateFilter) -> some View {
        Button {
            viewModel.selectedFilter = filter
        } label: {
            HStack(spacing: 10) {
                Image(systemName: filter.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(viewModel.selectedFilter == filter ? Color.accentColor : .secondary)

                Text(filter.rawValue)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.count(for: filter))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.selectedFilter == filter ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        viewModel.selectedFilter == filter
                            ? Color.accentColor.opacity(0.12)
                            : Color(nsColor: .separatorColor).opacity(0.18),
                        in: Capsule()
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
                .background(
                    viewModel.selectedFilter == filter
                    ? Color.accentColor.opacity(0.09)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(filter.rawValue)
        .accessibilityValue("\(viewModel.count(for: filter)) sessions")
        .accessibilityHint(viewModel.selectedFilter == filter ? "Current session filter." : "Filters the session list.")
        .accessibilityAddTraits(viewModel.selectedFilter == filter ? .isSelected : [])
    }

    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { appState.selectedTranscriptID },
            set: { appState.selectedTranscriptID = $0 }
        )
    }

    var body: some View {
        EmptyView()
    }
}
