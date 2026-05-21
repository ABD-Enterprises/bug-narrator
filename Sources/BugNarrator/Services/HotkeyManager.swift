import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class HotkeySettingsBinder {
    private let hotkeyManager: any HotkeyManaging
    private var cancellables = Set<AnyCancellable>()

    init(hotkeyManager: any HotkeyManaging) {
        self.hotkeyManager = hotkeyManager
    }

    func bind(settingsStore: SettingsStore) {
        cancellables.removeAll()

        settingsStore.$startRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .startRecording)
            }
            .store(in: &cancellables)

        settingsStore.$stopRecordingHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .stopRecording)
            }
            .store(in: &cancellables)

        settingsStore.$screenshotHotkeyShortcut
            .removeDuplicates()
            .sink { [weak self] shortcut in
                self?.hotkeyManager.register(shortcut: shortcut, for: .captureScreenshot)
            }
            .store(in: &cancellables)

        register(assignments: settingsStore.hotkeyAssignments)
    }

    private func register(assignments: [(action: HotkeyAction, shortcut: HotkeyShortcut)]) {
        for assignment in assignments {
            hotkeyManager.register(shortcut: assignment.shortcut, for: assignment.action)
        }
    }
}

@MainActor
final class HotkeyActionDispatcher {
    private let statusPhase: () -> AppStatus.Phase
    private let startRecording: () async -> Void
    private let stopRecording: () async -> Void
    private let captureScreenshot: () async -> Void

    init(
        statusPhase: @escaping () -> AppStatus.Phase,
        startRecording: @escaping () async -> Void,
        stopRecording: @escaping () async -> Void,
        captureScreenshot: @escaping () async -> Void
    ) {
        self.statusPhase = statusPhase
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        self.captureScreenshot = captureScreenshot
    }

    func handle(_ action: HotkeyAction) {
        switch action {
        case .startRecording:
            Task {
                await startRecording()
            }
        case .stopRecording:
            guard statusPhase() == .recording else {
                return
            }
            Task {
                await stopRecording()
            }
        case .captureScreenshot:
            Task {
                await captureScreenshot()
            }
        }
    }
}

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
