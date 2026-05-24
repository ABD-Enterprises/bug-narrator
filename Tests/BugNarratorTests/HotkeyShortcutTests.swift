import AppKit
import Carbon.HIToolbox
import XCTest
@testable import BugNarrator

final class HotkeyShortcutTests: XCTestCase {
    func testDisabledShortcutHasNoDisplayOrCarbonModifiers() {
        let shortcut = HotkeyShortcut.disabled

        XCTAssertFalse(shortcut.isEnabled)
        XCTAssertEqual(shortcut.displayString, "Not Set")
        XCTAssertNil(shortcut.displayStringIfEnabled)
        XCTAssertEqual(shortcut.carbonModifiers, 0)
    }

    func testShortcutDisplaysSupportedModifiersInStableOrder() {
        let modifiers = NSEvent.ModifierFlags.command
            .union(.option)
            .union(.control)
            .union(.shift)
            .rawValue
        let shortcut = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_B), modifiers: modifiers)

        XCTAssertTrue(shortcut.isEnabled)
        XCTAssertEqual(shortcut.displayString, "Ctrl+Opt+Shift+Cmd+B")
        XCTAssertEqual(shortcut.displayStringIfEnabled, "Ctrl+Opt+Shift+Cmd+B")
    }

    func testShortcutConvertsOnlySupportedEventModifiersToCarbonFlags() {
        let shortcut = HotkeyShortcut(
            keyCode: UInt32(kVK_ANSI_M),
            modifiers: NSEvent.ModifierFlags.command.union(.option).rawValue
        )

        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(cmdKey), 0)
        XCTAssertNotEqual(shortcut.carbonModifiers & UInt32(optionKey), 0)
        XCTAssertEqual(shortcut.carbonModifiers & UInt32(controlKey), 0)
        XCTAssertEqual(shortcut.carbonModifiers & UInt32(shiftKey), 0)
    }

    func testUnknownKeyCodeUsesNumericFallbackName() {
        let shortcut = HotkeyShortcut(
            keyCode: 999,
            modifiers: NSEvent.ModifierFlags.command.rawValue
        )

        XCTAssertEqual(shortcut.displayString, "Cmd+Key 999")
    }

    func testModifierKeyCodesAreRejectedAsTriggerKeys() {
        XCTAssertTrue(HotkeyShortcut.isModifierKeyCode(UInt16(kVK_Command)))
        XCTAssertTrue(HotkeyShortcut.isModifierKeyCode(UInt16(kVK_RightShift)))
        XCTAssertTrue(HotkeyShortcut.isModifierKeyCode(UInt16(kVK_Function)))
        XCTAssertFalse(HotkeyShortcut.isModifierKeyCode(UInt16(kVK_ANSI_A)))
    }
}
