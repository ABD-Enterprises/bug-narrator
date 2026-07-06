import Foundation

struct AppErrorNormalization: Equatable {
    let appError: AppError
    let operation: AppErrorOperation
    let underlyingErrorDescription: String?
}
