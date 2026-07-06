import Foundation
@testable import BugNarrator

final class MockHotkeyManager: HotkeyManaging {
    var onHotKeyPressed: ((HotkeyAction) -> Void)?
    private(set) var registeredShortcuts: [HotkeyAction: HotkeyShortcut] = [:]

    func register(shortcut: HotkeyShortcut, for action: HotkeyAction) {
        registeredShortcuts[action] = shortcut
    }

    func unregisterAll() {
        registeredShortcuts.removeAll()
    }
}
@MainActor
final class MockScreenCapturePermissionAccess: ScreenCapturePermissionAccessing {
    var permissionState: ScreenCapturePermissionState = .granted
    var requestedPermissionStates: [ScreenCapturePermissionState] = []
    private(set) var permissionRequestCallCount = 0

    func currentPermissionState() -> ScreenCapturePermissionState {
        permissionState
    }

    func requestPermissionIfNeeded() async -> ScreenCapturePermissionState {
        permissionRequestCallCount += 1

        if permissionState == .notDetermined, !requestedPermissionStates.isEmpty {
            permissionState = requestedPermissionStates.removeFirst()
        }

        return permissionState
    }
}

