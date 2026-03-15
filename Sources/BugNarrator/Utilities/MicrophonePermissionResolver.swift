import Foundation

enum MicrophonePermissionResolver {
    static func resolve(
        capturePermission: MicrophonePermissionState,
        audioPermission: MicrophonePermissionState
    ) -> MicrophonePermissionState {
        if capturePermission == .authorized || audioPermission == .authorized {
            return .authorized
        }

        if capturePermission == .notDetermined || audioPermission == .notDetermined {
            return .notDetermined
        }

        if capturePermission == .restricted || audioPermission == .restricted {
            return .restricted
        }

        return .denied
    }
}
