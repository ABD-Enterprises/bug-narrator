import Foundation

struct IssueExportPreflightFailure: Error {
    let error: AppError
    let opensSettings: Bool
}
