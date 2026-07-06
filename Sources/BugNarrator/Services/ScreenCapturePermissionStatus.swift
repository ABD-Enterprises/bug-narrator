import Foundation

enum ScreenCapturePermissionStatus: String, Equatable {
    case notDetermined
    case granted
    case denied
    case unavailable
    case captureSetupFailed
    case unknownError
}
