import SwiftUI

/// The menu bar's empty-library offer for the bundled sample session (#959).
///
/// The sample shipped in #374 with a button in the session library's empty
/// state. But a new install opens the menu bar, not the library window — so
/// the one surface a first-time user actually sees had no route to the one
/// artifact built to show them what the product does.
extension MenuBarView {
    var sampleSessionOffer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New here?")
                .font(.subheadline.weight(.semibold))

            Text("Open a bundled sample session to see a finished transcript with its extracted issues — no recording, no API key.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("See a Sample Session") {
                try? transcriptStore.add(SampleSession.make())
                appState.selectedTranscriptID = SampleSession.id
                appState.openTranscriptHistory()
            }
            .controlSize(.small)
            .accessibilityLabel("Open the bundled sample session")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
