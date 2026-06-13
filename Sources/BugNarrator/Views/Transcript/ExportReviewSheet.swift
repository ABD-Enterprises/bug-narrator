import AppKit
import SwiftUI

extension TranscriptView {
    func exportReviewSheet(_ review: IssueExportReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Similar \(review.destination.rawValue) Issues")
                    .font(.title3.weight(.semibold))

                Text("Review likely duplicates or related bugs before BugNarrator exports the selected issues.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(review.items) { item in
                        exportReviewItemCard(item)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    appState.cancelPendingExportReview()
                }

                Spacer()

                Button("Continue Export") {
                    Task {
                        await appState.confirmPendingExportReview()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canConfirmExportReview(review))
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 580)
    }

    func exportReviewItemCard(_ item: IssueExportReviewItem) -> some View {
        let liveItem = currentExportReviewItem(for: item.issue.id) ?? item

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(liveItem.issue.title)
                    .font(.headline)

                Text(liveItem.issue.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if liveItem.matches.isEmpty {
                Label("No likely open duplicates were found. This issue will export as new.", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    "Resolution",
                    selection: Binding(
                        get: { currentExportReviewItem(for: item.issue.id)?.resolution ?? item.resolution },
                        set: { newValue in
                            appState.setExportReviewResolution(newValue, for: item.issue.id)
                        }
                    )
                ) {
                    ForEach(SimilarIssueResolution.allCases) { resolution in
                        Text(resolution.rawValue).tag(resolution)
                    }
                }
                .pickerStyle(.menu)

                if let selectedMatch = liveItem.selectedMatch {
                    Label(
                        "This may be related to \(selectedMatch.remoteIdentifier) (\(selectedMatch.confidenceLabel) match).",
                        systemImage: "link"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(liveItem.matches) { match in
                        exportReviewMatchRow(
                            match,
                            issueID: item.issue.id,
                            isSelected: liveItem.selectedMatch?.id == match.id
                        )
                    }
                }

                if liveItem.resolution != .exportNew, liveItem.selectedMatch == nil {
                    Text("Choose an existing tracker issue before continuing.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    func exportReviewMatchRow(_ match: SimilarIssueMatch, issueID: UUID, isSelected: Bool) -> some View {
        Button {
            appState.selectExportReviewMatch(match.id, for: issueID)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(match.remoteIdentifier)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)

                    Text(match.title)
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 0)

                    Text(match.confidenceLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.45), in: Capsule())
                }

                if !match.summary.isEmpty {
                    Text(match.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                if !match.reasoning.isEmpty {
                    Text(match.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                if let remoteURL = match.remoteURL {
                    Link("Open Tracker Issue", destination: remoteURL)
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .separatorColor).opacity(0.18),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    func currentExportReviewItem(for issueID: UUID) -> IssueExportReviewItem? {
        appState.pendingExportReview?.items.first(where: { $0.issue.id == issueID })
    }

    func canConfirmExportReview(_ review: IssueExportReview) -> Bool {
        review.items.allSatisfy { item in
            let liveItem = currentExportReviewItem(for: item.issue.id) ?? item
            return liveItem.resolution == .exportNew || liveItem.selectedMatch != nil
        }
    }
}
