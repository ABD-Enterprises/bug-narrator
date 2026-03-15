import AppKit
import Carbon.HIToolbox
import Foundation

struct HotkeyShortcut: Codable, Equatable, Hashable {
    var keyCode: UInt32
    var modifiers: UInt

    static let disabled = HotkeyShortcut(keyCode: UInt32.max, modifiers: 0)
    static let supportedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    var isEnabled: Bool {
        keyCode != UInt32.max && !eventModifiers.isEmpty
    }

    var eventModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.supportedModifiers)
    }

    var carbonModifiers: UInt32 {
        guard isEnabled else {
            return 0
        }

        var flags: UInt32 = 0
        let eventModifiers = self.eventModifiers

        if eventModifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if eventModifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if eventModifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if eventModifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }

    var displayString: String {
        guard isEnabled else {
            return "Not Set"
        }

        var parts: [String] = []
        let flags = eventModifiers

        if flags.contains(.control) {
            parts.append("Ctrl")
        }
        if flags.contains(.option) {
            parts.append("Opt")
        }
        if flags.contains(.shift) {
            parts.append("Shift")
        }
        if flags.contains(.command) {
            parts.append("Cmd")
        }

        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "+")
    }

    var displayStringIfEnabled: String? {
        isEnabled ? displayString : nil
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case UInt16(kVK_Command),
             UInt16(kVK_RightCommand),
             UInt16(kVK_Shift),
             UInt16(kVK_RightShift),
             UInt16(kVK_Option),
             UInt16(kVK_RightOption),
             UInt16(kVK_Control),
             UInt16(kVK_RightControl),
             UInt16(kVK_CapsLock),
             UInt16(kVK_Function):
            return true
        default:
            return false
        }
    }

    private static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_ForwardDelete): "Forward Delete",
        UInt32(kVK_LeftArrow): "Left Arrow",
        UInt32(kVK_RightArrow): "Right Arrow",
        UInt32(kVK_UpArrow): "Up Arrow",
        UInt32(kVK_DownArrow): "Down Arrow",
        UInt32(kVK_F1): "F1",
        UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5",
        UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7",
        UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11",
        UInt32(kVK_F12): "F12"
    ]
}
