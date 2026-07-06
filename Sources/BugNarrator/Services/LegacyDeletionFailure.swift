import Foundation

/// A redacted description of a legacy-secret deletion that failed. Returned
/// (never thrown) so the caller can log it without aborting the primary
/// operation — the canonical-service delete is what actually matters.
struct LegacyDeletionFailure: Equatable {
    let service: String
    let redactedDetail: String
}
