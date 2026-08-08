import AVFoundation
import CoreGraphics
import SwiftUI

/// Footer, menu actions, modifier-key monitoring, and status presentation
/// helpers (#433 slice 5, final).
///
/// Byte-preserving relocation of `footerSection`, `runMenuAction`, the
/// modifier-key monitor lifecycle, `sessionControlsSubtitle`, `hotkeyLine`,
/// `statusTint`, and `statusBadgeTitle`.
extension MenuBarView {
    var footerSection: some View {
        HStack(spacing: 10) {
            Button("Settings") {
                appState.openSettings()
            }

            Spacer()

            Text(metadata.versionDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Quit") {
                appState.requestApplicationTermination()
            }
        }
    }

    func runMenuAction(
        delayNanoseconds: UInt64 = 250_000_000,
        action: @escaping @MainActor () async -> Void
    ) {
        dismiss()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await action()
        }
    }

    func refreshModifierKeys() {
        isOptionKeyPressed = NSEvent.modifierFlags.contains(.option)
    }

    func startModifierKeyMonitoring() {
        guard modifierKeyMonitor == nil else {
            return
        }

        modifierKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            isOptionKeyPressed = event.modifierFlags.contains(.option)
            return event
        }
    }

    func stopModifierKeyMonitoring() {
        guard let modifierKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(modifierKeyMonitor)
        self.modifierKeyMonitor = nil
    }

    var sessionControlsSubtitle: String {
        switch appState.status.phase {
        case .idle:
            return "The control window is the single place for recording actions."
        case .recording:
            return "Keep the controls open and use them or the hotkeys without reopening the menu."
        case .transcribing:
            return "Recording has stopped. The control window stays available while transcription finishes."
        case .success:
            return "Use the control window to start the next session when you are ready."
        case .error:
            return "Fix the current issue, then continue from the control window."
        }
    }

    func hotkeyLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) hotkey")
        .accessibilityValue(value)
    }

    var statusTint: Color {
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

    var statusBadgeTitle: String {
        if appState.status.phase == .error, let currentError = appState.currentError {
            return currentError.statusTitle(for: appState.settingsStore.aiProvider)
        }

        return appState.status.title
    }
}
