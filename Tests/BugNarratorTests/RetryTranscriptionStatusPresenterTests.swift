import XCTest
@testable import BugNarrator

@MainActor
final class RetryTranscriptionStatusPresenterTests: XCTestCase {
    func testPresentRetryStartedSetsProgressStatus() {
        let harness = RetryTranscriptionStatusPresenterHarness()

        harness.presenter.presentRetryStarted(progressMessage: "Retrying transcription from preserved audio...")

        XCTAssertEqual(
            harness.presentationState.status,
            .transcribing("Retrying transcription from preserved audio...")
        )
        XCTAssertNil(harness.presentationState.currentError)
        XCTAssertEqual(harness.showSettingsCallCount, 0)
        XCTAssertEqual(harness.showTranscriptCallCount, 0)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testPresentRetryContextFailureUsesRecoveryStatusAndOpensSettings() {
        let harness = RetryTranscriptionStatusPresenterHarness()

        harness.presenter.presentRetryContextFailure(
            appError: .missingAPIKey,
            opensSettings: true,
            statusMessage: "Recording saved locally. Add your OpenAI API key in Settings."
        )

        XCTAssertEqual(
            harness.presentationState.status,
            .error("Recording saved locally. Add your OpenAI API key in Settings.")
        )
        XCTAssertEqual(harness.presentationState.currentError, .missingAPIKey)
        XCTAssertEqual(harness.showSettingsCallCount, 1)
        XCTAssertEqual(harness.showTranscriptCallCount, 0)
        XCTAssertTrue(harness.telemetryRecorder.recordedEvents.isEmpty)
    }

    func testPresentRetryContextFailureWithoutStatusDelegatesToErrorPresenter() throws {
        let harness = RetryTranscriptionStatusPresenterHarness()

        harness.presenter.presentRetryContextFailure(
            appError: .transcriptionFailure("The saved retry session is unavailable."),
            opensSettings: false,
            statusMessage: nil
        )

        XCTAssertEqual(
            harness.presentationState.status,
            .error("Transcription failed: The saved retry session is unavailable.")
        )
        XCTAssertEqual(
            harness.presentationState.currentError,
            .transcriptionFailure("The saved retry session is unavailable.")
        )
        XCTAssertEqual(harness.showSettingsCallCount, 0)
        XCTAssertEqual(harness.showTranscriptCallCount, 0)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "present_error")
        XCTAssertEqual(telemetry.metadata["operation"], "retry_transcription")
        XCTAssertEqual(telemetry.metadata["error_type"], "transcription_failure")
    }

    func testPresentRetryableFailureLogsStatusAndOpensRecoverySurfaces() throws {
        let harness = RetryTranscriptionStatusPresenterHarness()
        let failure = PendingTranscriptionRetryFailure(
            session: TranscriptSession(
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                transcript: "",
                duration: 4,
                model: "whisper-1",
                languageHint: nil,
                prompt: nil
            ),
            appError: .invalidAPIKey,
            statusMessage: "Recording saved locally. Replace the rejected OpenAI API key in Settings."
        )

        harness.presenter.presentRetryableFailure(failure)

        XCTAssertEqual(
            harness.presentationState.status,
            .error("Recording saved locally. Replace the rejected OpenAI API key in Settings.")
        )
        XCTAssertEqual(harness.presentationState.currentError, .invalidAPIKey)
        XCTAssertEqual(harness.showSettingsCallCount, 1)
        XCTAssertEqual(harness.showTranscriptCallCount, 1)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "retry_pending_transcription")
        XCTAssertEqual(telemetry.metadata["operation"], "retry_transcription")
        XCTAssertEqual(telemetry.metadata["error_type"], "invalid_api_key")
    }

    func testPresentFailureDelegatesToErrorPresenterAndOpensSettingsWhenNeeded() throws {
        let harness = RetryTranscriptionStatusPresenterHarness()

        harness.presenter.presentFailure(AppError.missingAPIKey)

        XCTAssertEqual(harness.presentationState.status, .error(AppError.missingAPIKey.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, .missingAPIKey)
        XCTAssertEqual(harness.showSettingsCallCount, 1)
        XCTAssertEqual(harness.showTranscriptCallCount, 0)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "present_error")
        XCTAssertEqual(telemetry.metadata["operation"], "retry_transcription")
        XCTAssertEqual(telemetry.metadata["error_type"], "missing_api_key")
    }
}

@MainActor
private final class RetryTranscriptionStatusPresenterHarness {
    let presentationState: AppPresentationState
    let telemetryRecorder: MockOperationalTelemetryRecorder
    let errorPresenter: AppErrorPresenter
    let presenter: RetryTranscriptionStatusPresenter
    private let windowCalls: WindowCallRecorder

    var showSettingsCallCount: Int {
        windowCalls.showSettingsCallCount
    }

    var showTranscriptCallCount: Int {
        windowCalls.showTranscriptCallCount
    }

    init() {
        let presentationState = AppPresentationState()
        let telemetryRecorder = MockOperationalTelemetryRecorder()
        let windowCalls = WindowCallRecorder()
        self.presentationState = presentationState
        self.telemetryRecorder = telemetryRecorder
        self.windowCalls = windowCalls
        let errorPresenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
        )
        self.errorPresenter = errorPresenter
        self.presenter = RetryTranscriptionStatusPresenter(
            errorPresenter: errorPresenter,
            showSettingsWindow: {
                windowCalls.showSettingsCallCount += 1
            },
            showTranscriptWindow: {
                windowCalls.showTranscriptCallCount += 1
            }
        )
    }

    func lastAppErrorTelemetry(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (name: String, metadata: [String: String]) {
        try XCTUnwrap(
            telemetryRecorder.recordedEvents.last { $0.name == TelemetryEvent.appError.rawValue },
            file: file,
            line: line
        )
    }
}

private final class WindowCallRecorder {
    var showSettingsCallCount = 0
    var showTranscriptCallCount = 0
}
