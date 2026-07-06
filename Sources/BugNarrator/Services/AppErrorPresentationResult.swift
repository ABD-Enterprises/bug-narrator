import Foundation

struct AppErrorPresentationResult: Equatable {
    let appError: AppError
    let shouldOpenSettingsWindow: Bool
}
