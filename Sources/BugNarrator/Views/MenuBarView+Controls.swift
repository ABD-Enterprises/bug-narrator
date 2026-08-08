import AVFoundation
import CoreGraphics
import SwiftUI

/// Recording controls, microphone level, and screen-recording permission
/// (#433 slice 4).
///
/// Byte-preserving relocation of `controlsSection`, `microphoneLevelSection`,
/// `screenRecordingPermissionSection`, `assignedHotkeyLines`, and
/// `syncMicrophoneLevelMonitoring`.
extension MenuBarView {
    var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording Controls")
                    .font(.headline)

                Text(sessionControlsSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Show Recording Controls") {
                runMenuAction {
                    appState.openRecordingControls()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityHint("Opens the recording controls window.")

            microphoneLevelSection
            screenRecordingPermissionSection

            switch appState.status.phase {
            case .idle:
                Text("Open the control window to start, stop, and capture screenshots that automatically mark important moments. Global shortcuts stay active too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .recording:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recording is active. Keep the control window parked where you want it while you keep testing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("\(appState.activeTimelineMomentCount) timeline moments  •  \(appState.activeScreenshotCount) screenshots")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .transcribing:
                Text("The control window can stay open while BugNarrator uploads audio and prepares the transcript.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .success:
                Text("The latest session is ready in the session library. Reopen the control window when you want to start the next pass.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .error:
                Text("Use the recovery guidance above, then continue from the control window.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !assignedHotkeyLines.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Global Hotkeys")
                        .font(.footnote.weight(.semibold))

                    ForEach(assignedHotkeyLines, id: \.label) { line in
                        hotkeyLine(label: line.label, value: line.value)
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    var microphoneLevelSection: some View {
        if appState.settingsStore.recordingAudioSource.usesMicrophone {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("Mic Level")
                        .font(.footnote.weight(.semibold))

                    Spacer()

                    Text(microphoneLevelMonitor.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LevelMeterView(level: microphoneLevelMonitor.currentLevel)
                    .frame(height: 8)
                    .accessibilityLabel("Microphone input level")
                    .accessibilityValue(microphoneLevelMonitor.state.accessibilityValue(level: microphoneLevelMonitor.currentLevel))

                if microphoneLevelMonitor.state == .permissionNeeded && !shouldShowSetupBanner {
                    Button("Open Microphone Settings") {
                        appState.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    var screenRecordingPermissionSection: some View {
        if screenRecordingSetupIncomplete {
            VStack(alignment: .leading, spacing: 7) {
                Label("Screenshot access is not enabled", systemImage: "camera.viewfinder")
                    .font(.footnote.weight(.semibold))

                Text("Recording can continue without screenshots. Enable Screen Recording if you want BugNarrator to capture screenshots during a session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Screen Recording Settings") {
                    appState.openScreenRecordingPrivacySettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open Screen Recording privacy settings")
                .accessibilityHint("Opens the macOS privacy settings for screen recording access")
            }
            .padding(.vertical, 2)
        }
    }

    var assignedHotkeyLines: [(label: String, value: String)] {
        [
            ("Start", appState.settingsStore.startRecordingHotkeyShortcut.displayStringIfEnabled),
            ("Stop", appState.settingsStore.stopRecordingHotkeyShortcut.displayStringIfEnabled),
            ("Screenshot", appState.settingsStore.screenshotHotkeyShortcut.displayStringIfEnabled)
        ]
        .compactMap { label, value in
            guard let value else {
                return nil
            }

            return (label: label, value: value)
        }
    }

    func syncMicrophoneLevelMonitoring() {
        guard appState.settingsStore.recordingAudioSource.usesMicrophone else {
            microphoneLevelMonitor.stop()
            return
        }

        switch appState.status.phase {
        case .idle, .success, .error:
            microphoneLevelMonitor.start()
        case .recording, .transcribing:
            microphoneLevelMonitor.stop()
        }
    }

}
