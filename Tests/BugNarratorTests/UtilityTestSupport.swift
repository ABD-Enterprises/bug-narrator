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

final class MockURLHandler: URLOpening {
    private(set) var openedURLs: [URL] = []
    var shouldSucceed = true
    var openResults: [Bool] = []

    @discardableResult
    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        if !openResults.isEmpty {
            return openResults.removeFirst()
        }

        return shouldSucceed
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

