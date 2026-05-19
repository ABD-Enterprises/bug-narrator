import XCTest
@testable import BugNarrator

@MainActor
final class ScreenshotCoordinatorTests: XCTestCase {
    func testCaptureScreenshotReturnsScreenshotAndRestoresSelectionWindow() async throws {
        let screenshotService = MockScreenshotCaptureService()
        let harness = try ScreenshotCoordinatorHarness(screenshotCaptureService: screenshotService)
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        let markerID = UUID()
        var selectionWillBeginCount = 0
        var selectionDidEndCount = 0

        let result = try await harness.coordinator.captureScreenshot(
            in: recordingSession,
            prefix: "capture",
            index: 1,
            elapsedTime: 12,
            associatedMarkerID: markerID,
            onSelectionWillBegin: {
                selectionWillBeginCount += 1
            },
            onSelectionDidEnd: {
                selectionDidEndCount += 1
            },
            isSessionActive: { $0 == recordingSession.sessionID }
        )

        guard case .captured(let screenshot) = result else {
            return XCTFail("Expected captured screenshot.")
        }
        XCTAssertEqual(selectionWillBeginCount, 1)
        XCTAssertEqual(selectionDidEndCount, 1)
        XCTAssertEqual(harness.selectionService.selectRegionCallCount, 1)
        XCTAssertEqual(screenshotService.capturedRects, [CGRect(x: 20, y: 20, width: 120, height: 80)])
        XCTAssertEqual(screenshot.elapsedTime, 12)
        XCTAssertEqual(screenshot.associatedMarkerID, markerID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshot.filePath))
        XCTAssertFalse(harness.coordinator.isCaptureInProgress)
    }

    func testCaptureScreenshotWithDeniedPermissionDoesNotOpenSelection() async throws {
        let screenshotService = MockScreenshotCaptureService()
        let harness = try ScreenshotCoordinatorHarness(
            permissionState: .denied,
            screenshotCaptureService: screenshotService
        )
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        var selectionWillBeginCount = 0
        var selectionDidEndCount = 0

        do {
            _ = try await harness.coordinator.captureScreenshot(
                in: recordingSession,
                prefix: "capture",
                index: 1,
                elapsedTime: 4,
                associatedMarkerID: UUID(),
                onSelectionWillBegin: {
                    selectionWillBeginCount += 1
                },
                onSelectionDidEnd: {
                    selectionDidEndCount += 1
                },
                isSessionActive: { _ in true }
            )
            XCTFail("Expected permission denial.")
        } catch let error as AppError {
            XCTAssertEqual(error, .screenRecordingPermissionDenied)
        }

        XCTAssertEqual(selectionWillBeginCount, 0)
        XCTAssertEqual(selectionDidEndCount, 0)
        XCTAssertEqual(harness.selectionService.selectRegionCallCount, 0)
        XCTAssertEqual(screenshotService.capturedRects, [])
        XCTAssertFalse(harness.coordinator.isCaptureInProgress)
    }

    func testConcurrentCaptureRequestIsRejectedWhileSelectionIsActive() async throws {
        let selectionStarted = expectation(description: "selection started")
        let selectionService = MockScreenshotSelectionService()
        selectionService.suspendUntilCancelled = true
        selectionService.onSelectRegionStart = {
            selectionStarted.fulfill()
        }
        let harness = try ScreenshotCoordinatorHarness(selectionService: selectionService)
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()

        async let firstCapture = harness.coordinator.captureScreenshot(
            in: recordingSession,
            prefix: "capture",
            index: 1,
            elapsedTime: 2,
            associatedMarkerID: UUID(),
            onSelectionWillBegin: {},
            onSelectionDidEnd: {},
            isSessionActive: { _ in true }
        )
        await fulfillment(of: [selectionStarted], timeout: 1.0)

        do {
            _ = try await harness.coordinator.captureScreenshot(
                in: recordingSession,
                prefix: "capture",
                index: 2,
                elapsedTime: 3,
                associatedMarkerID: UUID(),
                onSelectionWillBegin: {},
                onSelectionDidEnd: {},
                isSessionActive: { _ in true }
            )
            XCTFail("Expected duplicate capture rejection.")
        } catch let error as AppError {
            XCTAssertEqual(
                error,
                .screenshotCaptureFailure("Wait for the current screenshot to finish, then try again.")
            )
        }

        harness.coordinator.cancelPendingSelection(reason: "Test cleanup cancels pending screenshot selection.")
        guard case .cancelled = try await firstCapture else {
            return XCTFail("Expected the first capture to be cancelled.")
        }
        XCTAssertEqual(selectionService.cancelActiveSelectionCallCount, 1)
        XCTAssertFalse(harness.coordinator.isCaptureInProgress)
    }

    func testCaptureFailureRemovesPartialFileAndRestoresSelectionWindow() async throws {
        let screenshotService = PartialFailureScreenshotCaptureService()
        let harness = try ScreenshotCoordinatorHarness(screenshotCaptureService: screenshotService)
        defer { harness.cleanup() }

        let recordingSession = try harness.makeRecordingSession()
        var selectionWillBeginCount = 0
        var selectionDidEndCount = 0

        do {
            _ = try await harness.coordinator.captureScreenshot(
                in: recordingSession,
                prefix: "capture",
                index: 1,
                elapsedTime: 8,
                associatedMarkerID: UUID(),
                onSelectionWillBegin: {
                    selectionWillBeginCount += 1
                },
                onSelectionDidEnd: {
                    selectionDidEndCount += 1
                },
                isSessionActive: { _ in true }
            )
            XCTFail("Expected capture failure.")
        } catch let error as AppError {
            XCTAssertEqual(error, .screenshotCaptureFailure("partial write failed"))
        }

        let partialURL = try XCTUnwrap(screenshotService.capturedURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertEqual(selectionWillBeginCount, 1)
        XCTAssertEqual(selectionDidEndCount, 1)
        XCTAssertFalse(harness.coordinator.isCaptureInProgress)
    }
}

@MainActor
private final class ScreenshotCoordinatorHarness {
    let rootDirectoryURL: URL
    let permissionAccess: MockScreenCapturePermissionAccess
    let artifactsService: MockArtifactsService
    let selectionService: MockScreenshotSelectionService
    let coordinator: ScreenshotCoordinator

    init(
        permissionState: ScreenCapturePermissionState = .granted,
        screenshotCaptureService: any ScreenshotCapturing = MockScreenshotCaptureService(),
        selectionService: MockScreenshotSelectionService = MockScreenshotSelectionService()
    ) throws {
        let fileManager = FileManager.default
        rootDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("BugNarratorScreenshotCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        permissionAccess = MockScreenCapturePermissionAccess()
        permissionAccess.permissionState = permissionState
        artifactsService = MockArtifactsService(
            rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts", isDirectory: true)
        )
        self.selectionService = selectionService
        coordinator = ScreenshotCoordinator(
            screenCapturePermissionService: ScreenCapturePermissionService(permissionAccess: permissionAccess),
            screenshotCaptureService: screenshotCaptureService,
            screenshotSelectionService: selectionService,
            artifactsService: artifactsService
        )
    }

    func makeRecordingSession() throws -> RecordingSessionDraft {
        let sessionID = UUID()
        let artifactsDirectoryURL = try artifactsService.createArtifactsDirectory(for: sessionID)
        return RecordingSessionDraft(sessionID: sessionID, artifactsDirectoryURL: artifactsDirectoryURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectoryURL)
    }
}

@MainActor
private final class PartialFailureScreenshotCaptureService: ScreenshotCapturing {
    private(set) var capturedURL: URL?

    func validateCaptureAvailability() async -> AppError? {
        nil
    }

    func captureScreenshot(in rect: CGRect, to url: URL) async throws {
        capturedURL = url
        try Data("partial".utf8).write(to: url)
        throw AppError.screenshotCaptureFailure("partial write failed")
    }
}
