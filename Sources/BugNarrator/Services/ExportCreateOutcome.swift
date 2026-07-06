import Foundation

/// Outcome of a single create attempt, classified for the retry loop.
enum ExportCreateOutcome {
    case success(remoteIdentifier: String, remoteURL: URL?)
    case transient(AppError, retryAfterSeconds: Int?)
    case permanent(AppError)
}
