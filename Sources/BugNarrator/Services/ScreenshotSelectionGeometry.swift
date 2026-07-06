import Foundation

struct ScreenshotSelectionGeometry {
    static func normalizedSelectionRect(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        minimumDimension: CGFloat = 4
    ) -> CGRect? {
        let rect = CGRect(
            x: min(startPoint.x, endPoint.x),
            y: min(startPoint.y, endPoint.y),
            width: abs(endPoint.x - startPoint.x),
            height: abs(endPoint.y - startPoint.y)
        ).integral

        guard rect.width >= minimumDimension, rect.height >= minimumDimension else {
            return nil
        }

        return rect
    }
}

