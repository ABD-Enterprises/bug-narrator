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
