import Foundation

/// Thrown by `withAsyncTimeout` when the wrapped operation does not finish
/// within the allotted time.
struct AsyncTimeoutError: Error, Equatable {}

/// Runs `operation`, returning normally if it finishes within `seconds`. If the
/// deadline elapses first, `onTimeout` is invoked (e.g. to cancel an underlying
/// `AVAssetExportSession`) and `AsyncTimeoutError` is thrown. The operation task
/// is cancelled once either branch wins, so a well-behaved operation can observe
/// cancellation and stop work.
///
/// This exists because some operations — notably `AVAssetExportSession`'s
/// completion-handler-based export — provide no internal timeout, so a hung
/// encoder would otherwise suspend the awaiting task forever.
func withAsyncTimeout(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> Void,
    onTimeout: @escaping @Sendable () -> Void = {}
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            onTimeout()
            throw AsyncTimeoutError()
        }

        defer { group.cancelAll() }
        // Surface the result (or error) of whichever task finishes first.
        try await group.next()
    }
}
