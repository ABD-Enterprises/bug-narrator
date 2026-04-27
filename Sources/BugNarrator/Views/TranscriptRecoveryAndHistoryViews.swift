import SwiftUI

struct PendingTranscriptionBanner: View {
    let count: Int
    let hasAPIKey: Bool
    let hasRecoveredRecording: Bool
    let openLatest: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: hasRecoveredRecording ? "waveform.badge.magnifyingglass" : "arrow.clockwise.circle")
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(hasRecoveredRecording ? "Open Latest Recovered Recording" : "Open Latest Retry Needed Session") {
                    openLatest()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if !hasAPIKey {
                    Button("Open Settings") {
                        openSettings()
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

    private var title: String {
        if count == 1 {
            return hasRecoveredRecording ? "1 recovered recording needs transcription" : "1 session needs transcription retry"
        }

        return hasRecoveredRecording ? "\(count) sessions include recovered recordings" : "\(count) sessions need transcription retry"
    }

    private var message: String {
        if hasRecoveredRecording {
            return "BugNarrator found audio from an unexpected quit and imported it into the session library. Open the latest recovered item to transcribe it."
        }

        return "These sessions were recorded successfully and kept in the library because transcription could not finish. Open the latest one to retry after fixing your OpenAI API key."
    }
}

struct StorageRecoveryBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "externaldrive.badge.checkmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct TranscriptQualityFindingsView: View {
    let findings: [TranscriptQualityFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(findings) { finding in
                Label(finding.message, systemImage: icon(for: finding))
                    .font(.subheadline)
                    .foregroundStyle(finding.severity == .error ? .red : .orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for finding: TranscriptQualityFinding) -> String {
        switch finding.kind {
        case .repeatedText:
            return "repeat"
        case .abruptEnding:
            return "text.badge.exclamationmark"
        case .shortTranscript:
            return "text.magnifyingglass"
        }
    }
}

struct ExportHistorySummaryView: View {
    let receipts: [ExportReceipt]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(receipts.prefix(5), id: \.fingerprint) { receipt in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(receipt.destination.rawValue, systemImage: icon(for: receipt))
                        .font(.subheadline.weight(.semibold))

                    Text(receipt.remoteIdentifier ?? receipt.state.rawValue.capitalized)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if let remoteURL = receipt.remoteURL {
                        Link("Open", destination: remoteURL)
                            .font(.caption.weight(.semibold))
                    }
                }

                Text(receipt.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if receipts.count > 5 {
                Text("\(receipts.count - 5) older export receipt(s) retained locally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func icon(for receipt: ExportReceipt) -> String {
        switch receipt.state {
        case .pending:
            return "clock.arrow.circlepath"
        case .succeeded:
            return "checkmark.seal"
        }
    }
}
