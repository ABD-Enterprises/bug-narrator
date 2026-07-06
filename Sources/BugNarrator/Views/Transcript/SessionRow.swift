import SwiftUI

struct SessionRow: View {
    let entry: SessionLibraryEntry
    @ObservedObject var appState: AppState
    @ObservedObject var transcriptStore: TranscriptStore

    var body: some View {
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

                    if appState.isUnsaved(entry.id) {
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

            Text(sessionPreview(for: entry))
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

        if appState.isUnsaved(entry.id) {
            components.append("Unsaved")
        }

        let preview = sessionPreview(for: entry).trimmingCharacters(in: .whitespacesAndNewlines)
        if !preview.isEmpty {
            components.append(preview)
        }

        return components.joined(separator: ". ")
    }

    private func sessionPreview(for entry: SessionLibraryEntry) -> String {
        guard entry.isPendingTranscription,
              let session = transcriptStore.session(with: entry.id) else {
            return entry.preview
        }

        return session.preview(for: appState.settingsStore.aiProvider)
    }
}
