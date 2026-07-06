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

    func captureDisplayImage(
        for display: ScreenCaptureDisplaySnapshot,
        sourceRect: CGRect?
    ) async throws -> CapturedDisplayImage {
        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.current
        } catch {
            throw Self.mapCaptureError(error)
        }

        guard let shareableDisplay = shareableContent.displays.first(where: { $0.displayID == display.displayID }) else {
            throw AppError.screenshotCaptureFailure("The selected display was no longer available for capture.")
        }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let excludedApplications = shareableContent.applications.filter { $0.processID == currentProcessID }

        let filter = SCContentFilter(
            display: shareableDisplay,
            excludingApplications: excludedApplications,
            exceptingWindows: []
        )
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let configuration = SCStreamConfiguration()
        let relativeSourceRect = sourceRect?.standardized.integral
        let captureFrame = relativeSourceRect.map {
            CGRect(
                x: display.frame.minX + $0.minX,
                y: display.frame.minY + $0.minY,
                width: $0.width,
                height: $0.height
            )
        } ?? display.frame

        let scaleX = display.frame.width > 0 ? CGFloat(display.pixelWidth) / display.frame.width : 1
        let scaleY = display.frame.height > 0 ? CGFloat(display.pixelHeight) / display.frame.height : 1

        if let relativeSourceRect {
            configuration.sourceRect = relativeSourceRect
            configuration.width = size_t(max(1, Int((relativeSourceRect.width * scaleX).rounded(.up))))
            configuration.height = size_t(max(1, Int((relativeSourceRect.height * scaleY).rounded(.up))))
        } else {
            configuration.width = size_t(max(1, display.pixelWidth))
            configuration.height = size_t(max(1, display.pixelHeight))
        }

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

        return CapturedDisplayImage(display: display, capturedFrame: captureFrame, image: image)
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
