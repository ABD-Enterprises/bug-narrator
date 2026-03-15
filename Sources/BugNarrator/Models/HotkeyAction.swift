import AppKit
import Carbon.HIToolbox
import Foundation

enum HotkeyAction: UInt32, Codable, CaseIterable, Identifiable {
    case startRecording = 1
    case stopRecording = 2
    case captureScreenshot = 4

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .startRecording:
            return "Start Recording"
        case .stopRecording:
            return "Stop Recording"
        case .captureScreenshot:
            return "Capture Screenshot"
        }
    }

    var legacyBuiltInShortcut: HotkeyShortcut? {
        switch self {
        case .startRecording:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: NSEvent.ModifierFlags.command
                    .union(.option)
                    .union(.control)
                    .rawValue
            )
        case .stopRecording:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: NSEvent.ModifierFlags.command
                    .union(.option)
                    .union(.control)
                    .union(.shift)
                    .rawValue
            )
        case .captureScreenshot:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: NSEvent.ModifierFlags.command
                    .union(.option)
                    .union(.control)
                    .union(.shift)
                    .rawValue
            )
        }
    }
}
