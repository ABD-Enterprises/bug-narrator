import Foundation

enum RecordingStartPreflightResult: Equatable {
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
