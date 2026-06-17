import SwiftUI

/// Session-library entry point plus pending-transcription retry controls
/// shown in the menu bar popover.
///
/// Extracted from `MenuBarView` as a focused section split for #433.
/// Behavior is unchanged; every action delegates to `AppState`.
@MainActor
struct MenuSessionLibraryCardView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Open Session Library") {
                appState.openTranscriptHistory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHint("Opens the session library window.")

            if transcriptStore.pendingTranscriptionSessionCount > 0 {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(pendingTranscriptionSummary)
                        .font(.footnote.weight(.semibold))

                    Text(
                        appState.settingsStore.aiProvider.requiresAPIKey
                            ? "Restore or replace the \(appState.settingsStore.aiProvider.displayName) API key in Settings if needed, then retry the saved session."
                            : "Confirm the \(appState.settingsStore.aiProvider.displayName) setup in Settings if needed, then retry the saved session."
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        if appState.needsAPIKeySetup {
                            Button("Open Settings") {
                                appState.openSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if transcriptStore.pendingTranscriptionSessionCount == 1 {
                            Button("Retry Transcription") {
                                retryLatestPendingTranscription()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(appState.retryingSessionID != nil)
                            .help("Retry transcription for the saved session without opening the library.")
                        } else {
                            Button("Retry Latest") {
                                retryLatestPendingTranscription()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(appState.retryingSessionID != nil)
                            .help("Retry transcription for the most recent saved session.")

                            Button("Open Retry Needed Session") {
                                openPendingTranscriptionSession()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        Button("View Library") {
                            appState.openTranscriptHistory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var pendingTranscriptionSummary: String {
        let count = transcriptStore.pendingTranscriptionSessionCount
        return count == 1
            ? "1 saved session is waiting for transcription retry."
            : "\(count) saved sessions are waiting for transcription retry."
    }

    private func openPendingTranscriptionSession() {
        if let sessionID = transcriptStore.latestPendingTranscriptionSession?.id {
            appState.selectedTranscriptID = sessionID
        }

        appState.openTranscriptHistory()
    }

    private func retryLatestPendingTranscription() {
        guard let sessionID = transcriptStore.latestPendingTranscriptionSession?.id else {
            return
        }

        Task {
            await appState.retryPendingTranscription(for: sessionID)
        }
    }
}
