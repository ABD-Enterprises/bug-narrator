import XCTest
@testable import BugNarrator

final class HotkeyManagerTests: XCTestCase {
    func testInstallAndRemoveEventHandlerAcrossLifecyclesDoesNotCrash() {
        // Each HotkeyManager installs an application-global Carbon event handler in
        // init and must remove it in deinit. The handler's userData is an unretained
        // pointer to the manager, so leaving it installed across deallocs would let a
        // global hotkey fire against freed memory. Repeated create/dealloc cycles
        // exercise the install/remove pairing.
        for _ in 0..<5 {
            autoreleasepool {
                _ = HotkeyManager()
            }
        }
    }
}
