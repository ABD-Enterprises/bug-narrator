import AppKit
import Foundation
import ImageIO

@MainActor
final class ScreenshotPreviewCache {
    static let shared = ScreenshotPreviewCache()

    private let cache = NSCache<NSURL, NSImage>()

    private init() {
        cache.countLimit = 64
    }

    func previewImage(for fileURL: URL, maxPixelSize: CGFloat = 720) -> NSImage? {
        let cacheKey = fileURL as NSURL
        if let cachedImage = cache.object(forKey: cacheKey) {
            return cachedImage
        }

        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize)
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let image = NSImage(cgImage: thumbnail, size: .zero)
        cache.setObject(image, forKey: cacheKey)
        return image
    }

    func removeImage(for fileURL: URL) {
        cache.removeObject(forKey: fileURL as NSURL)
    }

    func removeAllImages() {
        cache.removeAllObjects()
    }
}
