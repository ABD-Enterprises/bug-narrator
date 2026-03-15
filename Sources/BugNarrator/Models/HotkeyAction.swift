import Carbon.HIToolbox
import Foundation

enum HotkeyAction: UInt32, Codable, CaseIterable, Identifiable {
    case startRecording = 1
    case stopRecording = 2
    case insertMarker = 3
    case captureScreenshot = 4

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .startRecording:
            return "Start Recording"
        case .stopRecording:
            return "Stop Recording"
        case .insertMarker:
            return "Insert Marker"
        case .captureScreenshot:
            return "Capture Screenshot"
        }
    }

    var defaultShortcut: HotkeyShortcut {
        switch self {
        case .startRecording:
            return .default
        case .stopRecording:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_F),
                modifiers: HotkeyShortcut.default.eventModifiers.union(.shift).rawValue
            )
        case .insertMarker:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: HotkeyShortcut.default.eventModifiers.union(.shift).rawValue
            )
        case .captureScreenshot:
            return HotkeyShortcut(
                keyCode: UInt32(kVK_ANSI_S),
                modifiers: HotkeyShortcut.default.eventModifiers.union(.shift).rawValue
            )
        }
    }
}
