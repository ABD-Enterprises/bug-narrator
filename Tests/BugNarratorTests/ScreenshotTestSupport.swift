import Foundation
import XCTest
@testable import BugNarrator

final class MockScreenshotCaptureService: ScreenshotCapturing {
    var error: Error?
    var availabilityError: AppError?
    var delayNanoseconds: UInt64 = 0
    var onCaptureStart: (() -> Void)?
    private(set) var capturedRects: [CGRect] = []

    init(error: Error? = nil, delayNanoseconds: UInt64 = 0, onCaptureStart: (() -> Void)? = nil) {
        self.error = error
        self.delayNanoseconds = delayNanoseconds
        self.onCaptureStart = onCaptureStart
    }

    @MainActor
    func validateCaptureAvailability() async -> AppError? {
        availabilityError
    }

    @MainActor
    func captureScreenshot(in rect: CGRect, to url: URL) async throws {
        if let error {
            throw error
        }

        capturedRects.append(rect)
        onCaptureStart?()

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        try Data("screenshot".utf8).write(to: url)
    }
}

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

