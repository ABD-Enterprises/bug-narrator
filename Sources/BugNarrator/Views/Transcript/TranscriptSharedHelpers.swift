import AppKit
import SwiftUI

func normalizedOptionalReproductionStepText(_ value: String) -> String? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

func normalizedOptionalIssueText(_ value: String) -> String? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
}

extension TranscriptView {
    var dividerSection: some View {
        Divider()
            .overlay(Color(nsColor: .separatorColor).opacity(0.45))
    }

    func reviewSectionCard<Content: View>(
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

    func metadataChip(label: String, systemImage: String) -> some View {
        return Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.32), in: Capsule())
    }

    func emptyDetailState(title: String, message: String) -> some View {
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

    func resolveSession(for entry: SessionLibraryEntry) -> TranscriptSession? {
        if appState.currentTranscript?.id == entry.id {
            return appState.currentTranscript
        }

        return transcriptStore.session(with: entry.id)
    }

    func extractedIssue(sessionID: UUID, issueID: UUID) -> ExtractedIssue? {
        let sourceSession = liveSession(with: sessionID)
        return sourceSession?.issueExtraction?.issues.first(where: { $0.id == issueID })
    }

    func liveSession(with sessionID: UUID) -> TranscriptSession? {
        if appState.currentTranscript?.id == sessionID {
            return appState.currentTranscript
        }

        return transcriptStore.session(with: sessionID)
    }

    func screenshotActionLabel(for screenshot: SessionScreenshot, index: Int?, action: String) -> String {
        let ordinal = index.map { "Screenshot \($0 + 1)" } ?? "Screenshot"
        return "\(action) \(ordinal) at \(screenshot.timeLabel)"
    }
}
