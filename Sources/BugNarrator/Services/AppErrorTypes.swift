import Foundation

struct AppErrorNormalization: Equatable {
    let appError: AppError
    let operation: AppErrorOperation
    let underlyingErrorDescription: String?
}

struct AppErrorPresentationResult: Equatable {
    let appError: AppError
    let shouldOpenSettingsWindow: Bool
}
