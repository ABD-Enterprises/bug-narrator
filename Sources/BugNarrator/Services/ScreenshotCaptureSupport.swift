import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

struct ScreenCaptureDisplaySnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

struct CapturedDisplayImage {
    let display: ScreenCaptureDisplaySnapshot
    let capturedFrame: CGRect
    let image: CGImage
}

protocol ScreenCaptureImageProviding {
    @MainActor
    func availableDisplays() async throws -> [ScreenCaptureDisplaySnapshot]
    @MainActor
    func captureDisplayImage(
        for display: ScreenCaptureDisplaySnapshot,
        sourceRect: CGRect?
    ) async throws -> CapturedDisplayImage
}
protocol ScreenshotImageWriting {
    @MainActor
    func writePNG(_ image: CGImage, to url: URL) throws
}

struct PNGScreenshotImageWriter: ScreenshotImageWriting {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writePNG(_ image: CGImage, to url: URL) throws {
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL
            .appendingPathComponent(".\(UUID().uuidString)")
            .appendingPathExtension("png")

        do {
            guard let destination = CGImageDestinationCreateWithURL(
                temporaryURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw AppError.screenshotCaptureFailure("The screenshot file could not be created.")
            }

            CGImageDestinationAddImage(destination, image, nil)

            guard CGImageDestinationFinalize(destination) else {
                throw AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.")
            }

            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }

            try fileManager.moveItem(at: temporaryURL, to: url)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
