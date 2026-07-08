import SwiftUI

struct RawTranscriptSection: View {
    let session: TranscriptSession
    let availableWidth: CGFloat
    @ObservedObject var appState: AppState

    var body: some View {
        let entries = ReviewWorkspace.timelineEntries(
            for: session,
            provider: appState.settingsStore.aiProvider
        )

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

    private func screenshotActionLabel(for screenshot: SessionScreenshot, index: Int?, action: String) -> String {
        let ordinal = index.map { "Screenshot \($0 + 1)" } ?? "Screenshot"
        return "\(action) \(ordinal) at \(screenshot.timeLabel)"
    }
}
