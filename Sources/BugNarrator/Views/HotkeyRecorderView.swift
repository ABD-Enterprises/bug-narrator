import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var shortcut: HotkeyShortcut
    let defaultShortcut: HotkeyShortcut

    @State private var isCapturing = false
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button(isCapturing ? "Press Shortcut" : shortcut.displayString) {
                    if isCapturing {
                        stopCapture()
                    } else {
                        startCapture()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Default") {
                    shortcut = defaultShortcut
                }

                Button("Disable") {
                    shortcut = .disabled
                }
                .disabled(shortcut == .disabled)
            }

            Text(isCapturing ? "Press Escape to cancel shortcut capture." : "Capture a key combination with at least one modifier.")
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
