import Foundation

extension AppState {
    // MARK: - Methods

    func captureScreenshot() async {
        await screenshotCaptureController.captureScreenshot()
    }

    // MARK: - Computed properties

    var prepareForScreenshotSelection: (() -> Void)? {
        get { screenshotCaptureController.prepareForScreenshotSelection }
        set { screenshotCaptureController.prepareForScreenshotSelection = newValue }
    }
    var restoreAfterScreenshotSelection: (() -> Void)? {
        get { screenshotCaptureController.restoreAfterScreenshotSelection }
        set { screenshotCaptureController.restoreAfterScreenshotSelection = newValue }
    }

    var isScreenshotCaptureInProgress: Bool {
        screenshotCaptureController.isCaptureInProgress
    }
}
