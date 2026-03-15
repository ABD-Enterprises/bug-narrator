import SwiftUI

struct RecordingControlPanelView: View {
    @ObservedObject var appState: AppState

    let onStartSession: () -> Void
    let onStopSession: () -> Void
    let onInsertMarker: () -> Void
    let onCaptureScreenshot: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            statusSummary
            controlGrid
            footer
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recording Controls")
                .font(.title3.weight(.semibold))

            Text("Keep this panel open while you narrate. Use it or the global hotkeys to mark moments and capture screenshots without reopening the menu.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(appState.status.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)

                Spacer()

                if appState.status.phase == .recording {
                    Text(appState.elapsedTimeString)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                }
            }

            Text(statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.status.phase == .recording {
                Text("\(appState.activeMarkerCount) markers • \(appState.activeScreenshotCount) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controlGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                actionButton(
                    title: "Start Feedback Session",
                    shortcut: appState.settingsStore.startRecordingHotkeyShortcut.displayString,
                    prominence: .primary,
                    enabled: canStartSession,
                    action: onStartSession
                )

                actionButton(
                    title: "Stop Feedback Session",
                    shortcut: appState.settingsStore.stopRecordingHotkeyShortcut.displayString,
                    prominence: .secondary,
                    enabled: canStopSession,
                    action: onStopSession
                )
            }

            HStack(spacing: 12) {
                actionButton(
                    title: "Insert Marker",
                    shortcut: appState.settingsStore.markerHotkeyShortcut.displayString,
                    prominence: .secondary,
                    enabled: canUseLiveControls,
                    action: onInsertMarker
                )

                actionButton(
                    title: "Capture Screenshot",
                    shortcut: appState.settingsStore.screenshotHotkeyShortcut.displayString,
                    prominence: .secondary,
                    enabled: canUseLiveControls,
                    action: onCaptureScreenshot
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            if appState.status.phase == .recording && appState.needsAPIKeySetup {
                Text("You can keep recording without an API key. Add it in Settings before stopping if you want transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The panel stays open until you close it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
    }

    private var canStartSession: Bool {
        switch appState.status.phase {
        case .idle, .success, .error:
            return true
        case .recording, .transcribing:
            return false
        }
    }

    private var canStopSession: Bool {
        appState.status.phase == .recording
    }

    private var canUseLiveControls: Bool {
        appState.status.phase == .recording
    }

    private var statusMessage: String {
        if let detail = appState.status.detail, !detail.isEmpty {
            return detail
        }

        switch appState.status.phase {
        case .idle:
            return "Start a feedback session when you are ready to narrate the current walkthrough."
        case .recording:
            return "Recording is active. Add markers or capture screenshots as you move through the workflow."
        case .transcribing:
            return "The recording is finished. BugNarrator is preparing the transcript now."
        case .success:
            return "The latest session is ready in the session library."
        case .error:
            return "Fix the current issue, then use these controls to continue the workflow."
        }
    }

    private var statusTint: Color {
        switch appState.status.phase {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .transcribing:
            return .orange
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        shortcut: String,
        prominence: ButtonProminence,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        }

        if prominence == .primary {
            button
                .buttonStyle(.borderedProminent)
                .disabled(!enabled)
        } else {
            button
                .buttonStyle(.bordered)
                .disabled(!enabled)
        }
    }
}

private enum ButtonProminence {
    case primary
    case secondary
}
