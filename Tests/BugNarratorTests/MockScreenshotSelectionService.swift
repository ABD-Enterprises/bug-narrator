import Foundation
import XCTest
@testable import BugNarrator

@MainActor
final class MockScreenshotSelectionService: ScreenshotSelecting {
    var nextResult: ScreenshotSelectionResult = .selected(CGRect(x: 20, y: 20, width: 120, height: 80))
    var error: Error?
    var suspendUntilCancelled = false
    var onSelectRegionStart: (() -> Void)?
    private(set) var selectRegionCallCount = 0
    private(set) var cancelActiveSelectionCallCount = 0
    private var selectionContinuation: CheckedContinuation<ScreenshotSelectionResult, Error>?

    func selectRegion() async throws -> ScreenshotSelectionResult {
        selectRegionCallCount += 1
        onSelectRegionStart?()

        if let error {
            throw error
        }

        if suspendUntilCancelled {
            return try await withCheckedThrowingContinuation { continuation in
                selectionContinuation = continuation
            }
        }

        return nextResult
    }

    func cancelActiveSelection() {
        cancelActiveSelectionCallCount += 1
        selectionContinuation?.resume(returning: .cancelled)
        selectionContinuation = nil
    }
}

