import XCTest
@testable import BugNarrator

@MainActor
final class ScreenshotCaptureControllerTests: XCTestCase {
    func testCaptureScreenshotWithoutActiveSessionShowsNoActiveSessionError() async throws {
        let harness = try ScreenshotCaptureControllerHarness()
        defer { harness.cleanup() }

        await harness.controller.captureScreenshot()

        XCTAssertEqual(harness.presentationState.status.phase, .error)
        XCTAssertEqual(
            harness.presentationState.currentError,
            .noActiveSession("Start a feedback session before capturing a screenshot.")
        )
        XCTAssertEqual(harness.selectionService.selectRegionCallCount, 0)
    }

    func testCaptureScreenshotStoresMetadataAndCreatesAutoMarker() async throws {
        let harness = try ScreenshotCaptureControllerHarness()
        defer { harness.cleanup() }
        try await harness.startRecording()
        harness.audioRecorder.currentDuration = 12

        await harness.controller.captureScreenshot()

        let recordingSession = try XCTUnwrap(harness.recordingSessionController.activeRecordingSession)
        let screenshot = try XCTUnwrap(recordingSession.screenshots.first)
        let autoMarker = try XCTUnwrap(recordingSession.markers.last)

        XCTAssertEqual(recordingSession.screenshots.count, 1)
        XCTAssertEqual(recordingSession.markers.count, 1)
        XCTAssertEqual(screenshot.elapsedTime, 12)
        XCTAssertEqual(screenshot.associatedMarkerID, autoMarker.id)
        XCTAssertEqual(autoMarker.title, "Screenshot 1")
        XCTAssertNil(autoMarker.note)
        XCTAssertEqual(autoMarker.screenshotID, screenshot.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.filePath))
        XCTAssertEqual(harness.selectionService.selectRegionCallCount, 1)
        XCTAssertEqual(harness.presentationState.status.phase, .recording)
        XCTAssertEqual(harness.presentationState.status.detail, "Captured Screenshot 1.")
        XCTAssertEqual(harness.presentationState.transientToast?.message, "Screenshot captured")
    }

    func testCaptureScreenshotCancellationKeepsRecordingWithoutCreatingMarkerOrScreenshot() async throws {
        let selectionService = MockScreenshotSelectionService()
        selectionService.nextResult = .cancelled
        let harness = try ScreenshotCaptureControllerHarness(selectionService: selectionService)
        defer { harness.cleanup() }
        try await harness.startRecording()

        await harness.controller.captureScreenshot()

        XCTAssertEqual(harness.presentationState.status.phase, .recording)
        XCTAssertEqual(harness.presentationState.status.detail, "Recording in progress.")
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.markers.count, 0)
        XCTAssertEqual(harness.presentationState.transientToast?.message, "Screenshot canceled")
        XCTAssertEqual(harness.presentationState.transientToast?.style, .informational)
    }

    func testCaptureScreenshotBusyKeepsRecordingAndShowsBusyError() async throws {
        let selectionStarted = expectation(description: "selection started")
        let selectionService = MockScreenshotSelectionService()
        selectionService.suspendUntilCancelled = true
        selectionService.onSelectRegionStart = {
            selectionStarted.fulfill()
        }
        let harness = try ScreenshotCaptureControllerHarness(selectionService: selectionService)
        defer { harness.cleanup() }
        try await harness.startRecording()

        async let firstCapture: Void = harness.controller.captureScreenshot()
        await fulfillment(of: [selectionStarted], timeout: 1.0)
        await harness.controller.captureScreenshot()

        XCTAssertEqual(harness.presentationState.status.phase, .recording)
        XCTAssertEqual(
            harness.presentationState.currentError,
            .screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
        )
        harness.controller.cancelPendingSelection(reason: "Test cleanup cancels pending screenshot selection.")
        _ = await firstCapture

        XCTAssertEqual(selectionService.cancelActiveSelectionCallCount, 1)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.markers.count, 0)
    }

    func testCaptureScreenshotFailureKeepsRecordingAndShowsMessage() async throws {
        let harness = try ScreenshotCaptureControllerHarness(
            screenshotCaptureService: MockScreenshotCaptureService(
                error: AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.")
            )
        )
        defer { harness.cleanup() }
        try await harness.startRecording()

        await harness.controller.captureScreenshot()

        XCTAssertEqual(harness.presentationState.status.phase, .recording)
        XCTAssertEqual(
            harness.presentationState.status.detail,
            AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.").userMessage
        )
        XCTAssertEqual(
            harness.presentationState.currentError,
            AppError.screenshotCaptureFailure("The screenshot file could not be written to disk.")
        )
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.screenshots.count, 0)
        XCTAssertEqual(harness.recordingSessionController.activeRecordingSession?.markers.count, 0)
    }
}

@MainActor
private final class ScreenshotCaptureControllerHarness {
    let rootDirectoryURL: URL
    let audioRecorder: MockAudioRecorder
    let artifactsService: MockArtifactsService
    let presentationState: AppPresentationState
    let recordingSessionController: RecordingSessionController
    let screenshotCoordinator: ScreenshotCoordinator
    let selectionService: MockScreenshotSelectionService
    let controller: ScreenshotCaptureController

    init(
        screenshotCaptureService: MockScreenshotCaptureService = MockScreenshotCaptureService(),
        selectionService: MockScreenshotSelectionService = MockScreenshotSelectionService()
    ) throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorScreenshotCaptureControllerTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        audioRecorder = MockAudioRecorder()
        artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        presentationState = AppPresentationState()
        recordingSessionController = RecordingSessionController(
            audioRecorder: audioRecorder,
            microphonePermissionService: MicrophonePermissionService(permissionAccess: audioRecorder),
            artifactsService: artifactsService,
            recordingTimer: RecordingTimerViewModel()
        )
        self.selectionService = selectionService
        let permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = .granted
        screenshotCoordinator = ScreenshotCoordinator(
            screenCapturePermissionService: ScreenCapturePermissionService(permissionAccess: permissionAccess),
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: selectionService,
            artifactsService: artifactsService
        )
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: MockOperationalTelemetryRecorder()
        )
        controller = ScreenshotCaptureController(
            screenshotCoordinator: screenshotCoordinator,
            recordingSessionController: recordingSessionController,
            errorPresenter: errorPresenter,
            statusPhase: { [weak presentationState] in presentationState?.status.phase ?? .idle },
            elapsedDuration: { 0 },
            recordingDetailMessage: { "Recording in progress." },
            setStatus: { [weak presentationState] status, error in
                presentationState?.setStatus(status, error: error)
            },
            showToast: { [weak presentationState] message, style in
                presentationState?.showToast(TransientToast(message: message, style: style))
            }
        )
    }

    func startRecording() async throws {
        let outcome = await recordingSessionController.startSession(
            statusPhase: presentationState.status.phase,
            activityReason: "Recording test session"
        )
        guard case .started = outcome else {
            throw AppError.recordingFailure("The test recording session did not start.")
        }

        presentationState.setStatus(.recording("Recording in progress."))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}
