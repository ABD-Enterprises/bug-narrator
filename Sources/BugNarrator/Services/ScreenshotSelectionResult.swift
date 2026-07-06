import CoreGraphics
import Foundation

enum ScreenshotSelectionResult: Equatable {
    case selected(CGRect)
    case cancelled
}

