import CoreGraphics
import Foundation
import ImageIO
import XCTest
@testable import BugNarrator

final class ScreenshotCaptureServiceTests: XCTestCase {
    func testValidateCaptureAvailabilityReturnsPermissionDeniedError() async {
        let service = ScreenshotCaptureService(
            imageProvider: MockScreenCaptureImageProvider(error: AppError.screenRecordingPermissionDenied),
            imageWriter: PNGScreenshotImageWriter()
        )

        let error = await service.validateCaptureAvailability()

        XCTAssertEqual(error, .screenRecordingPermissionDenied)
    }

    func testCaptureScreenshotCreatesParentDirectoryAndWritesCompositePNG() async throws {
        let temporaryRoot = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let displayA = ScreenCaptureDisplaySnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 100, height: 50),
            pixelWidth: 100,
            pixelHeight: 50
        )
        let displayB = ScreenCaptureDisplaySnapshot(
            displayID: 2,
            frame: CGRect(x: 100, y: 0, width: 50, height: 50),
            pixelWidth: 50,
            pixelHeight: 50
        )

        let provider = MockScreenCaptureImageProvider(
            displays: [displayA, displayB],
            imagesByDisplayID: [
                1: try makeSolidImage(width: 100, height: 50, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                2: try makeSolidImage(width: 50, height: 50, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))
            ]
        )

        let service = ScreenshotCaptureService(
            imageProvider: provider,
            imageWriter: PNGScreenshotImageWriter()
        )

        let outputURL = temporaryRoot
            .appendingPathComponent("nested", isDirectory: true)
            .appendingPathComponent("capture.png")

        try await service.captureScreenshot(to: outputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 150)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 50)
    }

    func testCaptureScreenshotFailsWhenNoDisplaysAreAvailable() async {
        let service = ScreenshotCaptureService(
            imageProvider: MockScreenCaptureImageProvider(displays: []),
            imageWriter: PNGScreenshotImageWriter()
        )

        do {
            try await service.captureScreenshot(to: temporaryDirectoryURL().appendingPathComponent("capture.png"))
            XCTFail("Expected missing-display failure.")
        } catch {
            XCTAssertEqual(
                error as? AppError,
                .screenshotCaptureFailure("No displays were available to capture.")
            )
        }
    }

    private func temporaryDirectoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSolidImage(width: Int, height: Int, color: CGColor) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppError.screenshotCaptureFailure("Could not create a test screenshot image.")
        }

        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let image = context.makeImage() else {
            throw AppError.screenshotCaptureFailure("Could not finalize a test screenshot image.")
        }

        return image
    }
}

private struct MockScreenCaptureImageProvider: ScreenCaptureImageProviding {
    var displays: [ScreenCaptureDisplaySnapshot] = []
    var imagesByDisplayID: [CGDirectDisplayID: CGImage] = [:]
    var error: Error?

    @MainActor
    func availableDisplays() async throws -> [ScreenCaptureDisplaySnapshot] {
        if let error {
            throw error
        }

        return displays
    }

    @MainActor
    func captureDisplayImage(for display: ScreenCaptureDisplaySnapshot) async throws -> CapturedDisplayImage {
        if let error {
            throw error
        }

        guard let image = imagesByDisplayID[display.displayID] else {
            throw AppError.screenshotCaptureFailure("Missing mock image for display \(display.displayID).")
        }

        return CapturedDisplayImage(display: display, image: image)
    }
}
