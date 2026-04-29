import AppKit
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

@MainActor
final class ScreenshotSelectionService: ScreenshotSelecting {
    private var overlayController: ScreenshotSelectionOverlayController?
    private let screenshotLogger = DiagnosticsLogger(category: .screenshots)

    func selectRegion() async throws -> ScreenshotSelectionResult {
        guard overlayController == nil else {
            throw AppError.screenshotCaptureFailure("Finish the current screenshot selection before starting another.")
        }

        let controller = try ScreenshotSelectionOverlayController()
        overlayController = controller
        screenshotLogger.info(
            "screenshot_selection_started",
            "Presenting the screenshot region selection overlay."
        )

        defer {
            overlayController = nil
        }

        let result = await controller.presentSelectionOverlay()
        switch result {
        case .selected(let rect):
            screenshotLogger.info(
                "screenshot_selection_completed",
                "The screenshot region selection completed.",
                metadata: [
                    "width": "\(Int(rect.width))",
                    "height": "\(Int(rect.height))"
                ]
            )
        case .cancelled:
            screenshotLogger.info(
                "screenshot_selection_cancelled",
                "The screenshot region selection was cancelled."
            )
        }

        return result
    }

    func cancelActiveSelection() {
        overlayController?.cancelSelection()
    }
}

@MainActor
private final class ScreenshotSelectionOverlayController {
    private static let selectionTimeoutNanoseconds: UInt64 = 30_000_000_000

    private let window: ScreenshotSelectionOverlayWindow
    private let overlayView: ScreenshotSelectionOverlayView
    private var continuation: CheckedContinuation<ScreenshotSelectionResult, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var hasFinished = false
    private var didPushCursor = false

    init() throws {
        let overlayFrame = NSScreen.screens
            .map(\.frame)
            .reduce(into: CGRect.null) { partialResult, frame in
                partialResult = partialResult.union(frame)
            }
            .integral

        guard !overlayFrame.isNull, overlayFrame.width > 0, overlayFrame.height > 0 else {
            throw AppError.screenshotCaptureFailure("No screens were available for screenshot selection.")
        }

        overlayView = ScreenshotSelectionOverlayView(frame: CGRect(origin: .zero, size: overlayFrame.size))
        window = ScreenshotSelectionOverlayWindow(
            contentRect: overlayFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = overlayView
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.onResignedKey = { [weak self] in
            self?.cancelSelection()
        }
    }

    func presentSelectionOverlay() async -> ScreenshotSelectionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            overlayView.onSelectionCompleted = { [weak self] rect in
                guard let self else {
                    continuation.resume(returning: .cancelled)
                    return
                }

                self.complete(.selected(rect.offsetBy(
                    dx: self.window.frame.minX,
                    dy: self.window.frame.minY
                )))
            }

            overlayView.onSelectionCancelled = { [weak self] in
                self?.cancelSelection()
            }

            NSCursor.crosshair.push()
            didPushCursor = true
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlayView)
            NSApp.activate(ignoringOtherApps: true)
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.selectionTimeoutNanoseconds)
                guard !Task.isCancelled else {
                    return
                }

                self?.cancelSelection()
            }
        }
    }

    func cancelSelection() {
        complete(.cancelled)
    }

    private func complete(_ result: ScreenshotSelectionResult) {
        guard !hasFinished else {
            return
        }

        hasFinished = true
        timeoutTask?.cancel()
        timeoutTask = nil
        overlayView.onSelectionCompleted = nil
        overlayView.onSelectionCancelled = nil
        finishPresentation()

        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    private func finishPresentation() {
        window.orderOut(nil)
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }
}

private final class ScreenshotSelectionOverlayWindow: NSWindow {
    var onResignedKey: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignedKey?()
    }
}

private final class ScreenshotSelectionOverlayView: NSView {
    var onSelectionCompleted: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private let overlayCornerRadius: CGFloat = 8
    private var dragStartPoint: CGPoint?
    private var currentSelectionRect: CGRect?
    private var hasCompletedSelection = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let dimmedPath = NSBezierPath(rect: bounds)
        if let currentSelectionRect {
            dimmedPath.appendRect(currentSelectionRect)
            dimmedPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.28).setFill()
        dimmedPath.fill()

        drawInstructionHint()

        guard let currentSelectionRect else {
            return
        }

        drawSelectionChrome(for: currentSelectionRect)
        drawSelectionSizeLabel(for: currentSelectionRect)
    }

    override func mouseDown(with event: NSEvent) {
        guard !hasCompletedSelection else {
            return
        }

        dragStartPoint = convert(event.locationInWindow, from: nil)
        currentSelectionRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasCompletedSelection, let dragStartPoint else {
            return
        }

        let currentPoint = convert(event.locationInWindow, from: nil)
        currentSelectionRect = ScreenshotSelectionGeometry.normalizedSelectionRect(
            from: dragStartPoint,
            to: currentPoint,
            minimumDimension: 0
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !hasCompletedSelection else {
            return
        }

        guard let dragStartPoint else {
            completeSelection(with: nil)
            return
        }

        let endPoint = convert(event.locationInWindow, from: nil)
        let selectedRect = ScreenshotSelectionGeometry.normalizedSelectionRect(
            from: dragStartPoint,
            to: endPoint
        )

        self.dragStartPoint = nil
        currentSelectionRect = nil
        needsDisplay = true

        completeSelection(with: selectedRect)
    }

    override func cancelOperation(_ sender: Any?) {
        guard !hasCompletedSelection else {
            return
        }

        dragStartPoint = nil
        currentSelectionRect = nil
        needsDisplay = true
        completeSelection(with: nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            cancelOperation(nil)
            return
        }

        super.keyDown(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func completeSelection(with rect: CGRect?) {
        guard !hasCompletedSelection else {
            return
        }

        hasCompletedSelection = true
        if let rect {
            onSelectionCompleted?(rect)
        } else {
            onSelectionCancelled?()
        }
    }

    private func drawInstructionHint() {
        let message = "Drag to capture  •  Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96)
        ]
        let attributedString = NSAttributedString(string: message, attributes: attributes)
        let textSize = attributedString.size()
        let padding = NSSize(width: 16, height: 10)
        let hintRect = CGRect(
            x: bounds.midX - (textSize.width + padding.width * 2) / 2,
            y: bounds.maxY - textSize.height - 42,
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        ).integral

        let hintPath = NSBezierPath(roundedRect: hintRect, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.52).setFill()
        hintPath.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        hintPath.lineWidth = 1
        hintPath.stroke()

        attributedString.draw(in: hintRect.insetBy(dx: padding.width, dy: padding.height))
    }

    private func drawSelectionChrome(for rect: CGRect) {
        let selectionPath = NSBezierPath(
            roundedRect: rect,
            xRadius: overlayCornerRadius,
            yRadius: overlayCornerRadius
        )
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        selectionPath.fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = .zero
        shadow.set()

        NSColor.white.withAlphaComponent(0.96).setStroke()
        selectionPath.lineWidth = 2
        selectionPath.stroke()
        NSGraphicsContext.restoreGraphicsState()

        let innerRect = rect.insetBy(dx: 1.5, dy: 1.5)
        guard innerRect.width > 0, innerRect.height > 0 else {
            return
        }

        let innerPath = NSBezierPath(
            roundedRect: innerRect,
            xRadius: max(0, overlayCornerRadius - 1.5),
            yRadius: max(0, overlayCornerRadius - 1.5)
        )
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        innerPath.lineWidth = 1
        innerPath.stroke()
    }

    private func drawSelectionSizeLabel(for rect: CGRect) {
        let sizeText = "\(Int(rect.width)) × \(Int(rect.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.96)
        ]
        let attributedString = NSAttributedString(string: sizeText, attributes: attributes)
        let textSize = attributedString.size()
        let padding = NSSize(width: 10, height: 6)
        let labelRect = CGRect(
            x: rect.minX,
            y: max(bounds.minY + 16, rect.minY - textSize.height - 18),
            width: textSize.width + padding.width * 2,
            height: textSize.height + padding.height * 2
        ).integral

        let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.58).setFill()
        labelPath.fill()
        NSColor.white.withAlphaComponent(0.16).setStroke()
        labelPath.lineWidth = 1
        labelPath.stroke()

        attributedString.draw(in: labelRect.insetBy(dx: padding.width, dy: padding.height))
    }
}
