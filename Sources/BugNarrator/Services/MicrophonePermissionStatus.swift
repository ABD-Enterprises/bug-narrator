import Foundation

enum MicrophonePermissionStatus: String, Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailable
    case captureSetupFailed
    case unknownError
}
