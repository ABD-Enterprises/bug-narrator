import Foundation

@MainActor
final class ScreenshotCoordinator: ObservableObject {
    @Published private(set) var isCaptureInProgress = false

    private let screenCapturePermissionService: any ScreenCapturePermissionServicing
    private let screenshotCaptureService: any ScreenshotCapturing
    private let screenshotSelectionService: any ScreenshotSelecting
    private let artifactsService: any SessionArtifactsManaging
    private let fileManager: FileManager
    private let logger: DiagnosticsLogger

    init(
        screenCapturePermissionService: any ScreenCapturePermissionServicing,
        screenshotCaptureService: any ScreenshotCapturing,
        screenshotSelectionService: any ScreenshotSelecting,
        artifactsService: any SessionArtifactsManaging,
        fileManager: FileManager = .default,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .screenshots)
    ) {
        self.screenCapturePermissionService = screenCapturePermissionService
        self.screenshotCaptureService = screenshotCaptureService
        self.screenshotSelectionService = screenshotSelectionService
        self.artifactsService = artifactsService
        self.fileManager = fileManager
        self.logger = logger
    }

    func captureScreenshot(
        in recordingSession: RecordingSessionDraft,
        prefix: String,
        index: Int,
        elapsedTime: TimeInterval,
        associatedMarkerID: UUID?,
        onSelectionWillBegin: () -> Void,
        onSelectionDidEnd: () -> Void,
        isSessionActive: (UUID) -> Bool
    ) async throws -> ScreenshotCoordinatorResult {
        guard !isCaptureInProgress else {
            throw AppError.screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
        }

        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        let preflightResult = await screenCapturePermissionService.preflightForScreenshotCapture(
            screenshotCaptureService: screenshotCaptureService,
            hasActiveRecordingSession: true
        )
        if let preflightError = preflightResult.error {
            throw preflightError
        }

        onSelectionWillBegin()
        defer {
            onSelectionDidEnd()
        }

        let selectionResult = try await screenshotSelectionService.selectRegion()
        guard case let .selected(selectionRect) = selectionResult else {
            return .cancelled
        }

        let screenshotURL = artifactsService.makeScreenshotURL(
            in: recordingSession.artifactsDirectoryURL,
            prefix: prefix,
            index: index,
            elapsedTime: elapsedTime
        )

        do {
            try await screenshotCaptureService.captureScreenshot(in: selectionRect, to: screenshotURL)
        } catch {
            try? fileManager.removeItem(at: screenshotURL)
            throw error
        }

        guard isSessionActive(recordingSession.sessionID) else {
            try? fileManager.removeItem(at: screenshotURL)
            throw AppError.screenshotCaptureFailure("The session ended before the screenshot finished saving.")
        }

        return .captured(
            SessionScreenshot(
                elapsedTime: elapsedTime,
                filePath: screenshotURL.path,
                associatedMarkerID: associatedMarkerID
            )
        )
    }

    func cancelPendingSelection(reason: String) {
        guard isCaptureInProgress else {
            return
        }

        logger.info("screenshot_selection_cancel_requested", reason)
        screenshotSelectionService.cancelActiveSelection()
    }
}

enum ScreenshotCoordinatorResult {
    case captured(SessionScreenshot)
    case cancelled
}
