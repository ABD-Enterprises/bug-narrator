import AppKit
import XCTest
@testable import BugNarrator

@MainActor
final class ApplicationTerminationControllerTests: XCTestCase {
    func testApplicationShouldTerminateAllowsQuitWhenNotRecording() {
        let harness = ApplicationTerminationControllerHarness()

        let reply = harness.controller.applicationShouldTerminate()

        XCTAssertEqual(reply, .terminateNow)
        XCTAssertEqual(harness.cancelReasons, [])
        XCTAssertEqual(harness.recordingControlsShownCount, 0)
        XCTAssertEqual(harness.toasts.count, 0)
    }

    func testApplicationShouldTerminateCancelsQuitWhileRecording() {
        let harness = ApplicationTerminationControllerHarness()
        harness.statusPhase = .recording
        harness.activeRecordingSession = harness.makeRecordingSession()

        let reply = harness.controller.applicationShouldTerminate()

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertEqual(harness.cancelReasons, ["Quit was requested while recording, so pending screenshot selection was cancelled."])
        XCTAssertEqual(harness.recordingControlsShownCount, 1)
        XCTAssertEqual(harness.toasts.map(\.message), ["Stop recording before quitting BugNarrator."])
        XCTAssertEqual(harness.toasts.map(\.style), [.informational])
    }

    func testApplicationShouldTerminateCancelsQuitWhileTranscribing() {
        let harness = ApplicationTerminationControllerHarness()
        harness.statusPhase = .transcribing
        harness.activeRecordingSession = harness.makeRecordingSession()

        let reply = harness.controller.applicationShouldTerminate()

        XCTAssertEqual(reply, .terminateCancel)
        XCTAssertEqual(harness.cancelReasons, ["Quit was requested while transcription was finishing, so pending screenshot selection was cancelled."])
        XCTAssertEqual(harness.recordingControlsShownCount, 1)
        XCTAssertEqual(harness.toasts.map(\.message), ["Wait for transcription to finish saving before quitting BugNarrator."])
        XCTAssertEqual(harness.toasts.map(\.style), [.informational])
    }

    func testRequestApplicationTerminationInvokesInjectedTerminateOnlyWhenAllowed() {
        let allowedHarness = ApplicationTerminationControllerHarness()

        allowedHarness.controller.requestApplicationTermination()

        XCTAssertEqual(allowedHarness.terminateCount, 1)

        let blockedHarness = ApplicationTerminationControllerHarness()
        blockedHarness.statusPhase = .recording
        blockedHarness.activeRecordingSession = blockedHarness.makeRecordingSession()

        blockedHarness.controller.requestApplicationTermination()

        XCTAssertEqual(blockedHarness.terminateCount, 0)
        XCTAssertEqual(blockedHarness.recordingControlsShownCount, 1)
    }

    func testPrepareForApplicationTerminationRunsCleanup() {
        let harness = ApplicationTerminationControllerHarness()
        harness.statusPhase = .recording
        harness.activeRecordingSession = harness.makeRecordingSession()
        harness.isExtractingIssues = true
        harness.isExporting = true

        harness.controller.prepareForApplicationTermination()

        XCTAssertEqual(harness.dismissToastCount, 1)
        XCTAssertEqual(harness.unregisterHotkeysCount, 1)
        XCTAssertEqual(harness.stopTimerArguments, [false])
        XCTAssertEqual(harness.endActivityCount, 1)
    }
}

@MainActor
private final class ApplicationTerminationControllerHarness {
    struct CapturedToast {
        let message: String
        let style: TransientToastStyle
    }

    var statusPhase: AppStatus.Phase = .idle
    var activeRecordingSession: RecordingSessionDraft?
    var isExtractingIssues = false
    var isExporting = false
    var cancelReasons: [String] = []
    var recordingControlsShownCount = 0
    var toasts: [CapturedToast] = []
    var dismissToastCount = 0
    var unregisterHotkeysCount = 0
    var stopTimerArguments: [Bool] = []
    var endActivityCount = 0
    var terminateCount = 0

    lazy var controller = ApplicationTerminationController(
        statusPhase: { [weak self] in self?.statusPhase ?? .idle },
        activeRecordingSession: { [weak self] in self?.activeRecordingSession },
        isExtractingIssues: { [weak self] in self?.isExtractingIssues ?? false },
        isExporting: { [weak self] in self?.isExporting ?? false },
        cancelPendingScreenshotSelection: { [weak self] reason in self?.cancelReasons.append(reason) },
        showRecordingControls: { [weak self] in self?.recordingControlsShownCount += 1 },
        showToast: { [weak self] message, style in self?.toasts.append(CapturedToast(message: message, style: style)) },
        dismissToast: { [weak self] in self?.dismissToastCount += 1 },
        unregisterHotkeys: { [weak self] in self?.unregisterHotkeysCount += 1 },
        stopTimer: { [weak self] resetElapsed in self?.stopTimerArguments.append(resetElapsed) },
        endActivity: { [weak self] in self?.endActivityCount += 1 },
        terminateApplication: { [weak self] in self?.terminateCount += 1 }
    )

    func makeRecordingSession() -> RecordingSessionDraft {
        RecordingSessionDraft(
            sessionID: UUID(),
            artifactsDirectoryURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ApplicationTerminationControllerTests", isDirectory: true)
        )
    }
}
