import SwiftUI

struct RecordingHUDView: View {
    @ObservedObject var appState: AppState

    let onInsertMarker: () -> Void
    let onCaptureScreenshot: () -> Void
    let onStopSession: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("BugNarrator")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(appState.elapsedTimeString)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }

                Spacer()

                Button(action: onStopSession) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Stop feedback session")
            }

            HStack(spacing: 8) {
                Button(action: onInsertMarker) {
                    Label("Marker", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Insert marker")

                Button(action: onCaptureScreenshot) {
                    Label("Screenshot", systemImage: "camera.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Capture screenshot")
            }

            Text("\(appState.activeMarkerCount) markers • \(appState.activeScreenshotCount) screenshots")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .accessibilityElement(children: .contain)
    }
}
