import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
