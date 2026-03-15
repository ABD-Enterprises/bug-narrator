import SwiftUI

struct RecordingControlPanelView: View {
    @ObservedObject var appState: AppState

    let onStartSession: () -> Void
    let onStopSession: () -> Void
    let onInsertMarker: () -> Void
    let onCaptureScreenshot: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusSummary
            controlGrid
            footer
        }
        .padding(16)
        .frame(width: 332, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("BugNarrator Controls")
                    .font(.headline)

                Text("Recording actions live here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(statusBadgeTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusTint)
        }
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if appState.status.phase == .recording {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                }

                Text(statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

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

            if let localTestingNote {
                Text(localTestingNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsRecoveryButton {
                recoveryButton
            } else if appState.status.phase == .recording {
                Text("\(appState.activeMarkerCount) markers • \(appState.activeScreenshotCount) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var controlGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                actionButton(
                    title: "Start Recording",
                    shortcut: appState.settingsStore.startRecordingHotkeyShortcut.displayString,
                    prominence: .primary,
                    enabled: canStartSession,
                    action: onStartSession
                )

                actionButton(
                    title: "Stop Recording",
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
            Text(footerMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
    }

    private var footerMessage: String {
        if appState.status.phase == .recording && appState.needsAPIKeySetup {
            return "You can keep recording without an API key. Add it in Settings before stopping if you want transcription."
        }

        return "The controls stay open until you close them."
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

    private var statusHeadline: String {
        switch appState.status.phase {
        case .idle:
            return "Ready for the next feedback session."
        case .recording:
            return "Recording is active."
        case .transcribing:
            return "Preparing the transcript."
        case .success:
            return "Latest session ready."
        case .error:
            return appState.currentError?.recoveryHeadline ?? "Action needed before you continue."
        }
    }

    private var statusMessage: String {
        if let detail = appState.status.detail, !detail.isEmpty {
            return detail
        }

        switch appState.status.phase {
        case .idle:
            return "Start a feedback session when you are ready to narrate the current walkthrough."
        case .recording:
            return "Use these controls or the global hotkeys to mark moments and capture screenshots as you test."
        case .transcribing:
            return "The recording is finished. BugNarrator is uploading audio and waiting for transcription."
        case .success:
            return "Review the transcript in the session library, then start the next session from here."
        case .error:
            return "Resolve the current issue, then use these controls to continue the workflow."
        }
    }

    private var localTestingNote: String? {
        switch appState.currentError {
        case .microphonePermissionDenied, .microphonePermissionRestricted, .microphoneUnavailable:
            return appState.microphoneRecoveryLocalTestingNote
        default:
            return nil
        }
    }

    private var showsRecoveryButton: Bool {
        switch appState.currentError {
        case .microphonePermissionDenied, .microphonePermissionRestricted, .screenRecordingPermissionDenied:
            return true
        case let error?:
            return error.suggestsOpenAISettings
        case nil:
            return false
        }
    }

    @ViewBuilder
    private var recoveryButton: some View {
        switch appState.currentError {
        case .microphonePermissionDenied, .microphonePermissionRestricted:
            Button("Open Microphone Settings") {
                appState.openMicrophonePrivacySettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case .screenRecordingPermissionDenied:
            Button("Open Screen Recording Settings") {
                appState.openScreenRecordingPrivacySettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        case let error? where error.suggestsOpenAISettings:
            Button("Open Settings") {
                appState.openSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        default:
            EmptyView()
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

    private var statusBadgeTitle: String {
        if appState.status.phase == .error, let currentError = appState.currentError {
            return currentError.statusTitle
        }

        return appState.status.title
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
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
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
