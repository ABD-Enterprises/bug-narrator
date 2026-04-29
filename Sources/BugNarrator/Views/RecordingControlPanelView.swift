import AppKit
import SwiftUI

struct RecordingControlPanelView: View {
    @ObservedObject var appState: AppState

    let onStartSession: () -> Void
    let onStopSession: () -> Void
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
        .overlay(alignment: .top) {
            if let transientToast = appState.transientToast {
                Label(transientToast.message, systemImage: transientToast.style.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(transientToast.style == .success ? .green : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(.quaternary.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: appState.transientToast)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording controls dialog")
        .onChange(of: appState.transientToast?.message) { _, newMessage in
            announceAccessibilityMessage(newMessage)
        }
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
                        .accessibilityHidden(true)
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
                Text("\(appState.activeTimelineMomentCount) timeline moments • \(appState.activeScreenshotCount) screenshots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording status")
        .accessibilityValue(statusSummaryAccessibilityValue)
    }

    private var controlGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                actionButton(
                    title: "Start Recording",
                    shortcut: appState.settingsStore.startRecordingHotkeyShortcut.displayStringIfEnabled,
                    prominence: .primary,
                    enabled: canStartSession,
                    action: onStartSession
                )

                actionButton(
                    title: "Stop Recording",
                    shortcut: appState.settingsStore.stopRecordingHotkeyShortcut.displayStringIfEnabled,
                    prominence: .secondary,
                    enabled: canStopSession,
                    action: onStopSession
                )
            }

            actionButton(
                title: "Capture Screenshot",
                shortcut: appState.settingsStore.screenshotHotkeyShortcut.displayStringIfEnabled,
                prominence: .secondary,
                enabled: canUseLiveControls,
                action: onCaptureScreenshot
            )
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
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Closes the recording controls window.")
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
        appState.status.phase == .recording && !appState.isScreenshotCaptureInProgress
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
            return "Use these controls or any global hotkeys you assigned to capture screenshots whenever you want to mark an important moment."
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
        shortcut: String?,
        prominence: ButtonProminence,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let button = Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let shortcut {
                    Text(shortcut)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }

        if prominence == .primary {
            if enabled {
                button
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(title)
                    .accessibilityHint(actionButtonAccessibilityHint(shortcut: shortcut, enabled: enabled))
            } else {
                button
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .accessibilityLabel(title)
                    .accessibilityHint(actionButtonAccessibilityHint(shortcut: shortcut, enabled: enabled))
            }
        } else {
            button
                .buttonStyle(.bordered)
                .disabled(!enabled)
                .accessibilityLabel(title)
                .accessibilityHint(actionButtonAccessibilityHint(shortcut: shortcut, enabled: enabled))
        }
    }

    private var statusSummaryAccessibilityValue: String {
        var components = [statusHeadline]

        if appState.status.phase == .recording {
            components.append("Elapsed time \(appState.elapsedTimeString)")
        }

        components.append(statusMessage)

        if let localTestingNote {
            components.append(localTestingNote)
        }

        if appState.status.phase == .recording {
            components.append("\(appState.activeTimelineMomentCount) timeline moments")
            components.append("\(appState.activeScreenshotCount) screenshots")
        }

        return components.joined(separator: ". ")
    }

    private func actionButtonAccessibilityHint(shortcut: String?, enabled: Bool) -> String {
        if !enabled {
            return "Currently unavailable."
        }

        if let shortcut, !shortcut.isEmpty {
            return "Keyboard shortcut: \(shortcut)."
        }

        return "Available from the recording controls window."
    }

    private func announceAccessibilityMessage(_ message: String?) {
        guard let message, !message.isEmpty else {
            return
        }

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

private enum ButtonProminence {
    case primary
    case secondary
}
