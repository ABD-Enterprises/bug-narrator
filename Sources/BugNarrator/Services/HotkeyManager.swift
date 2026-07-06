import Carbon.HIToolbox
import Combine
import Foundation


final class HotkeyManager: HotkeyManaging {
    var onHotKeyPressed: ((HotkeyAction) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [HotkeyAction: EventHotKeyRef] = [:]
    private let hotKeySignature: OSType = 0x464D6963

    init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        unregisterAll()
        removeEventHandler()
    }

    func register(shortcut: HotkeyShortcut, for action: HotkeyAction) {
        unregister(action: action)

        guard shortcut.isEnabled else {
            return
        }

        var registeredRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )

        guard status == noErr, let registeredRef else {
            return
        }

        hotKeyRefs[action] = registeredRef
    }

    func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
    }

    private func unregister(action: HotkeyAction) {
        guard let hotKeyRef = hotKeyRefs.removeValue(forKey: action) else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
    }

    /// Removes the application-global Carbon event handler. Must be paired with
    /// `installEventHandlerIfNeeded()`: the handler's `userData` is an unretained
    /// pointer to `self`, so leaving it installed after deinit would let a global
    /// hotkey fire the C callback against freed memory.
    private func removeEventHandler() {
        guard let eventHandler else {
            return
        }

        RemoveEventHandler(eventHandler)
        self.eventHandler = nil
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandlerCallback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func handleHotKeyEvent(_ event: EventRef?) {
        guard let event else {
            return
        }

        var hotKeyID = EventHotKeyID()
        let result = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard result == noErr,
              hotKeyID.signature == hotKeySignature,
              let action = HotkeyAction(rawValue: hotKeyID.id) else {
            return
        }

        onHotKeyPressed?(action)
    }

    private static let eventHandlerCallback: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return noErr
        }

        let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
        manager.handleHotKeyEvent(event)
        return noErr
    }
}
