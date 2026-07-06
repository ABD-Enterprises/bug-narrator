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
