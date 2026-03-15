import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var shortcut: HotkeyShortcut

    @State private var isCapturing = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(shortcut.displayString)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(shortcut.isEnabled ? .primary : .secondary)
                    .frame(minWidth: 120, alignment: .leading)

                Button(isCapturing ? "Press Shortcut" : shortcut.isEnabled ? "Change" : "Assign") {
                    if isCapturing {
                        stopCapture()
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Clear") {
                    shortcut = .disabled
                }
                .disabled(shortcut == .disabled)
            }

            Text(
                isCapturing
                    ? "Press the shortcut you want to use, or press Escape to cancel."
                    : shortcut.isEnabled
                        ? "This action uses the shortcut shown above."
                        : "No shortcut assigned."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onDisappear {
            stopCapture()
        }
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopCapture()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(HotkeyShortcut.supportedModifiers)
            guard !modifiers.isEmpty, !HotkeyShortcut.isModifierKeyCode(event.keyCode) else {
                return nil
            }

            shortcut = HotkeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers.rawValue)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        isCapturing = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
