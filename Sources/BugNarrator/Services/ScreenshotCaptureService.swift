import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenCaptureDisplaySnapshot: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
}

struct CapturedDisplayImage {
    let display: ScreenCaptureDisplaySnapshot
    let image: CGImage
}

protocol ScreenCaptureImageProviding {
    @MainActor
    func availableDisplays() async throws -> [ScreenCaptureDisplaySnapshot]
    @MainActor
    func captureDisplayImage(for display: ScreenCaptureDisplaySnapshot) async throws -> CapturedDisplayImage
}

struct ScreenCaptureKitImageProvider: ScreenCaptureImageProviding {
    func availableDisplays() async throws -> [ScreenCaptureDisplaySnapshot] {
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            throw Self.mapCaptureError(error)
        }

        return shareableContent.displays
            .map { display in
                ScreenCaptureDisplaySnapshot(
                    displayID: display.displayID,
                    frame: display.frame.integral,
                    pixelWidth: display.width,
                    pixelHeight: display.height
                )
            }
            .sorted { lhs, rhs in
                if lhs.frame.minY == rhs.frame.minY {
                    return lhs.frame.minX < rhs.frame.minX
                }

                return lhs.frame.minY < rhs.frame.minY
            }
    }

    func captureDisplayImage(for display: ScreenCaptureDisplaySnapshot) async throws -> CapturedDisplayImage {
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            throw Self.mapCaptureError(error)
        }

        guard let shareableDisplay = shareableContent.displays.first(where: { $0.displayID == display.displayID }) else {
            throw AppError.screenshotCaptureFailure("The selected display was no longer available for capture.")
        }

        let filter = SCContentFilter(display: shareableDisplay, excludingApplications: [], exceptingWindows: [])
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        configuration.width = size_t(max(1, display.pixelWidth))
        configuration.height = size_t(max(1, display.pixelHeight))

        let image: CGImage
        do {
            image = try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                    if let image {
                        continuation.resume(returning: image)
                    } else {
                        continuation.resume(throwing: error ?? AppError.screenshotCaptureFailure("Screen capture failed."))
                    }
                }
            }
        } catch {
            throw Self.mapCaptureError(error)
        }

        return CapturedDisplayImage(display: display, image: image)
    }

    private static func mapCaptureError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
           nsError.code == SCStreamError.userDeclined.rawValue {
            return .screenRecordingPermissionDenied
        }

        return .screenshotCaptureFailure(nsError.localizedDescription)
    }
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

struct ScreenshotCaptureService: ScreenshotCapturing {
    private let imageProvider: any ScreenCaptureImageProviding
    private let imageWriter: any ScreenshotImageWriting
    private let screenshotLogger = DiagnosticsLogger(category: .screenshots)

    init(
        imageProvider: any ScreenCaptureImageProviding = ScreenCaptureKitImageProvider(),
        imageWriter: any ScreenshotImageWriting = PNGScreenshotImageWriter()
    ) {
        self.imageProvider = imageProvider
        self.imageWriter = imageWriter
    }

    @MainActor
    func validateCaptureAvailability() async -> AppError? {
        do {
            let displays = try await resolvedDisplaysForCapture()
            guard !displays.isEmpty else {
                return .screenshotCaptureFailure("No displays were available to capture.")
            }
            return nil
        } catch let error as AppError {
            return error
        } catch {
            return .screenshotCaptureFailure(error.localizedDescription)
        }
    }

    @MainActor
    func captureScreenshot(to url: URL) async throws {
        screenshotLogger.info(
            "screenshot_capture_requested",
            "Capturing a screenshot for the active review session.",
            metadata: ["file_name": url.lastPathComponent]
        )

        let displays = try await resolvedDisplaysForCapture()
        guard !displays.isEmpty else {
            screenshotLogger.error("screenshot_capture_no_displays", "No displays were available for ScreenCaptureKit.")
            throw AppError.screenshotCaptureFailure("No displays were available to capture.")
        }

        screenshotLogger.debug(
            "screenshot_displays_resolved",
            "ScreenCaptureKit resolved the active display layout.",
            metadata: ["display_count": "\(displays.count)"]
        )

        var capturedDisplays: [CapturedDisplayImage] = []
        capturedDisplays.reserveCapacity(displays.count)
        for display in displays {
            capturedDisplays.append(try await imageProvider.captureDisplayImage(for: display))
        }

        let image = try makeCompositeImage(from: capturedDisplays)
        try imageWriter.writePNG(image, to: url)
        screenshotLogger.info(
            "screenshot_capture_succeeded",
            "Saved a screenshot for the active review session.",
            metadata: [
                "file_name": url.lastPathComponent,
                "display_count": "\(capturedDisplays.count)"
            ]
        )
    }

    @MainActor
    private func resolvedDisplaysForCapture() async throws -> [ScreenCaptureDisplaySnapshot] {
        do {
            return try await imageProvider.availableDisplays()
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.screenshotCaptureFailure(error.localizedDescription)
        }
    }

    private func makeCompositeImage(from capturedDisplays: [CapturedDisplayImage]) throws -> CGImage {
        let frames = capturedDisplays.map(\.display.frame)
        let compositeBounds = frames.reduce(into: CGRect.null) { partialResult, frame in
            partialResult = partialResult.union(frame)
        }.integral

        guard !compositeBounds.isNull, compositeBounds.width > 0, compositeBounds.height > 0 else {
            throw AppError.screenshotCaptureFailure("No display content was available to capture.")
        }

        let width = Int(compositeBounds.width.rounded(.up))
        let height = Int(compositeBounds.height.rounded(.up))
        let colorSpace = capturedDisplays.first?.image.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AppError.screenshotCaptureFailure("BugNarrator could not prepare the screenshot image.")
        }

        context.interpolationQuality = .high

        for capturedDisplay in capturedDisplays {
            let frame = capturedDisplay.display.frame
            let drawRect = CGRect(
                x: frame.minX - compositeBounds.minX,
                y: frame.minY - compositeBounds.minY,
                width: frame.width,
                height: frame.height
            )
            context.draw(capturedDisplay.image, in: drawRect)
        }

        guard let image = context.makeImage() else {
            throw AppError.screenshotCaptureFailure("BugNarrator could not finish the screenshot image.")
        }

        return image
    }
}
