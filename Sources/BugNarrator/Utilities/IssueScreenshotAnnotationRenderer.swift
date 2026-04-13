import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RenderedIssueScreenshotAsset: Equatable {
    let fileURL: URL

    var fileName: String {
        fileURL.lastPathComponent
    }
}

struct IssueScreenshotAnnotationRenderer {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func writeAnnotatedScreenshot(
        for issue: ExtractedIssue,
        screenshot: SessionScreenshot,
        to directoryURL: URL
    ) throws -> RenderedIssueScreenshotAsset? {
        let annotations = issue.screenshotAnnotations(for: screenshot.id)
        guard !annotations.isEmpty else {
            return nil
        }

        guard let source = CGImageSourceCreateWithURL(screenshot.fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        let width = image.width
        let height = image.height
        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for annotation in annotations {
            draw(annotation: annotation, in: context, imageWidth: width, imageHeight: height)
        }

        guard let renderedImage = context.makeImage() else {
            return nil
        }

        let destinationURL = uniqueDestinationURL(
            in: directoryURL,
            fileName: annotatedFileName(for: screenshot, issueID: issue.id)
        )

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        CGImageDestinationAddImage(destination, renderedImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return RenderedIssueScreenshotAsset(fileURL: destinationURL)
    }

    private func annotatedFileName(for screenshot: SessionScreenshot, issueID: UUID) -> String {
        let baseURL = URL(fileURLWithPath: screenshot.fileName)
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let issuePrefix = issueID.uuidString.split(separator: "-").first.map(String.init) ?? issueID.uuidString
        return "\(baseName)-annotated-\(issuePrefix).png"
    }

    private func uniqueDestinationURL(in directoryURL: URL, fileName: String) -> URL {
        let baseURL = URL(fileURLWithPath: fileName)
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let fileExtension = baseURL.pathExtension.isEmpty ? "png" : baseURL.pathExtension
        var candidateURL = directoryURL.appendingPathComponent(fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidateURL.path) {
            candidateURL = directoryURL.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }

        return candidateURL
    }

    private func draw(
        annotation: IssueScreenshotAnnotation,
        in context: CGContext,
        imageWidth: Int,
        imageHeight: Int
    ) {
        let normalizedRect = annotation.normalizedRect
        let rect = CGRect(
            x: normalizedRect.origin.x * CGFloat(imageWidth),
            y: (1 - normalizedRect.origin.y - normalizedRect.height) * CGFloat(imageHeight),
            width: normalizedRect.width * CGFloat(imageWidth),
            height: normalizedRect.height * CGFloat(imageHeight)
        )

        let strokeColor = CGColor(red: 0.98, green: 0.33, blue: 0.21, alpha: 0.95)
        let fillColor = CGColor(red: 0.98, green: 0.33, blue: 0.21, alpha: 0.16)

        context.saveGState()
        context.setStrokeColor(strokeColor)
        context.setFillColor(fillColor)
        context.setLineWidth(max(4, min(rect.width, rect.height) * 0.04))
        context.addRect(rect)
        context.drawPath(using: .fillStroke)

        let anchor = CGPoint(x: rect.minX, y: rect.maxY)
        let arrowLength = max(18, min(CGFloat(imageWidth), CGFloat(imageHeight)) * 0.05)
        context.move(to: CGPoint(x: anchor.x - arrowLength, y: anchor.y + arrowLength))
        context.addLine(to: anchor)
        context.addLine(to: CGPoint(x: anchor.x + arrowLength * 0.45, y: anchor.y + arrowLength))
        context.strokePath()
        context.restoreGState()
    }
}
