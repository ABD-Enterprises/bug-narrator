import Foundation

extension IssueExtractionFailurePresenter {
    /// Runs a throwing issue-mutation operation, discarding any return value on success
    /// (the mutation controllers return `@discardableResult Bool`). On failure delegates
    /// to `presentFailure(error)`. Bridges the three do/catch delegators in
    /// `AppState+IssueExtraction.swift` (#578, renamed in #597).
    func attempt<T>(_ operation: () throws -> T) {
        do {
            _ = try operation()
        } catch {
            presentFailure(error)
        }
    }
}
