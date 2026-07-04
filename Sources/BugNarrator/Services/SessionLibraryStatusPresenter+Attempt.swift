import Foundation

extension SessionLibraryStatusPresenter {
    /// Runs a throwing session-library operation; on success invokes `success` with the
    /// returned value, on failure delegates to `presentFailure(error)`. Bridges the
    /// three do/catch delegators in `AppState+SessionLibrary.swift` (#578).
    func present<T>(_ operation: () throws -> T, success: (T) -> Void) {
        do {
            success(try operation())
        } catch {
            presentFailure(error)
        }
    }
}
