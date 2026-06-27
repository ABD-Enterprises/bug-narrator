import XCTest
@testable import BugNarrator

final class AsyncTimeoutTests: XCTestCase {
    func testReturnsWhenOperationFinishesBeforeDeadline() async throws {
        let ranOnTimeout = OneShotFlag()
        try await withAsyncTimeout(
            seconds: 5,
            operation: {
                // Completes well within the deadline.
            },
            onTimeout: { ranOnTimeout.set() }
        )
        XCTAssertFalse(ranOnTimeout.value)
    }

    func testThrowsTimeoutAndInvokesOnTimeoutWhenOperationHangs() async {
        let onTimeoutFired = OneShotFlag()

        do {
            try await withAsyncTimeout(
                seconds: 0.05,
                operation: {
                    // Simulates a non-completing export: suspends far longer than
                    // the deadline. It should be cancelled once the timeout wins.
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                },
                onTimeout: { onTimeoutFired.set() }
            )
            XCTFail("Expected withAsyncTimeout to throw AsyncTimeoutError")
        } catch is AsyncTimeoutError {
            XCTAssertTrue(onTimeoutFired.value)
        } catch {
            XCTFail("Expected AsyncTimeoutError, got \(error)")
        }
    }

    func testPropagatesOperationErrorWithoutWaitingForTimeout() async {
        struct SampleError: Error {}
        do {
            try await withAsyncTimeout(
                seconds: 5,
                operation: { throw SampleError() }
            )
            XCTFail("Expected the operation error to propagate")
        } catch is SampleError {
            // expected
        } catch {
            XCTFail("Expected SampleError, got \(error)")
        }
    }
}

/// Minimal thread-safe one-shot boolean for asserting an `@Sendable` callback ran.
private final class OneShotFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func set() {
        lock.lock(); defer { lock.unlock() }
        flag = true
    }

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }
}
