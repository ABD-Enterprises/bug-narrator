import SwiftUI

/// One-time explainer shown before the first system-audio recording, describing
/// the private aggregate audio device BugNarrator briefly creates.
struct SystemAudioExplainerView: View {
    @ObservedObject var appState: AppState
    @State private var suppressFuture = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Recording system audio", systemImage: "speaker.wave.2.fill")
                .font(.title3.weight(.semibold))

            explainerRow(
                title: "What this does",
                detail: "BugNarrator briefly creates a private virtual audio device to capture what's playing through your speakers. It's removed automatically when the recording ends."
            )
            explainerRow(
                title: "What you'll see in Audio MIDI Setup",
                detail: "While recording, a temporary \"BugNarrator\" aggregate device may appear in Audio MIDI Setup. That's expected — it disappears after the session."
            )
            explainerRow(
                title: "How to disable it",
                detail: "Switch the audio source back to \"Mic only\" in Settings → Recording Audio to stop capturing system audio."
            )

            Toggle("Don't show this again", isOn: $suppressFuture)
                .font(.subheadline)

            HStack {
                Spacer()
                Button("Cancel") {
                    appState.cancelSystemAudioExplainer()
                }
                .keyboardShortcut(.cancelAction)

                Button("Start Recording") {
                    Task { await appState.confirmSystemAudioExplainer(suppressFuture: suppressFuture) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func explainerRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
