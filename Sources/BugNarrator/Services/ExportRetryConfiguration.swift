import Foundation


/// Bounds retry of a single per-issue tracker create. POST issue-creation is not
/// blindly idempotent, so retries are only safe because the export loop reconciles
/// by the `bugnarrator-export-id` marker before re-creating (#502).
struct ExportRetryConfiguration: Sendable {
    let maxAttempts: Int
    let baseDelay: Duration

    static let `default` = ExportRetryConfiguration(maxAttempts: 3, baseDelay: .milliseconds(500))
    /// No real backoff — for tests that simulate transient-then-success.
    static let immediate = ExportRetryConfiguration(maxAttempts: 3, baseDelay: .zero)
}

