import SwiftUI

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
