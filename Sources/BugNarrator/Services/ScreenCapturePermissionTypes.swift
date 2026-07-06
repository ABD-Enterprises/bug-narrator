import Foundation

enum ScreenCapturePermissionState: Equatable {
    case granted
    case notDetermined
    case denied
    case unavailable
}

enum ScreenCapturePermissionStatus: String, Equatable {
    case notDetermined
    case granted
    case denied
    case unavailable
    case captureSetupFailed
    case unknownError
}

struct ScreenCaptureRecoveryGuidance: Equatable {
    let headline: String
    let message: String
}

enum ScreenshotCapturePreflightResult: Equatable {
    case success
    case blocked(AppError)
    case needsUserAction(AppError)
    case failure(AppError)

    var error: AppError? {
        switch self {
        case .success:
            return nil
        case .blocked(let error), .needsUserAction(let error), .failure(let error):
            return error
        }
    }
}

enum ScreenshotSelectionResult: Equatable {
    case selected(CGRect)
    case cancelled
}

