import Foundation

extension IssueMutationFailurePresenter {
    /// Runs a throwing issue-mutation operation, discarding any return value on success
    /// (the mutation controllers return `@discardableResult Bool`). On failure delegates
    /// to `presentFailure(error)`. Bridges the three do/catch delegators in
    /// `AppState+IssueMutation.swift` (#578).
    func attempt<T>(_ operation: () throws -> T) {
        do {
            _ = try operation()
        } catch {
            presentFailure(error)
        }
    }
}
