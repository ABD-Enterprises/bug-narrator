import Foundation
@testable import BugNarrator

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

