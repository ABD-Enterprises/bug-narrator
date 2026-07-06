import SwiftUI

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
