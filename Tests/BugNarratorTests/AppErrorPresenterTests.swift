import XCTest
@testable import BugNarrator

@MainActor
final class AppErrorPresenterTests: XCTestCase {
    func testSetStatusUpdatesPresentationState() {
        let harness = AppErrorPresenterHarness()

        harness.presenter.setStatus(.success("Saved."))

        XCTAssertEqual(harness.presentationState.status, .success("Saved."))
        XCTAssertNil(harness.presentationState.currentError)
    }

    func testPresentErrorNormalizesFallbackAndRecordsTelemetryMetadata() throws {
        let harness = AppErrorPresenterHarness()
        let underlyingError = NSError(
            domain: "AppErrorPresenterTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Disk is full"]
        )

        let result = harness.presenter.presentError(
            underlyingError,
            operation: .sessionLibrary,
            fallback: { .storageFailure($0) }
        )

        let appError = AppError.storageFailure("Disk is full")
        XCTAssertEqual(result, AppErrorPresentationResult(appError: appError, shouldOpenSettingsWindow: false))
        XCTAssertEqual(harness.presentationState.status, .error(appError.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, appError)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "present_error")
        XCTAssertEqual(telemetry.metadata["operation"], "session_library")
        XCTAssertEqual(telemetry.metadata["error_type"], "storage_failure")
        XCTAssertEqual(telemetry.metadata["underlying_error"], "Disk is full")
    }

    func testPresentErrorPassesThroughAppErrorAndRecommendsSettingsWhenNeeded() throws {
        let harness = AppErrorPresenterHarness()

        let result = harness.presenter.presentError(AppError.missingAPIKey, operation: .recordingStart)

        XCTAssertEqual(result, AppErrorPresentationResult(appError: .missingAPIKey, shouldOpenSettingsWindow: true))
        XCTAssertEqual(harness.presentationState.status, .error(AppError.missingAPIKey.userMessage))
        XCTAssertEqual(harness.presentationState.currentError, .missingAPIKey)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "present_error")
        XCTAssertEqual(telemetry.metadata["operation"], "recording_start")
        XCTAssertEqual(telemetry.metadata["error_type"], "missing_api_key")
        XCTAssertNil(telemetry.metadata["underlying_error"])
    }

    func testPresentPostTranscriptionErrorPrefixesStatusAndRecommendsSettingsForOpenAIErrors() throws {
        let harness = AppErrorPresenterHarness()

        let result = harness.presenter.presentPostTranscriptionError(AppError.invalidAPIKey)

        XCTAssertEqual(result, AppErrorPresentationResult(appError: .invalidAPIKey, shouldOpenSettingsWindow: true))
        XCTAssertEqual(
            harness.presentationState.status,
            .error("Transcript ready, but \(AppError.invalidAPIKey.userMessage)")
        )
        XCTAssertEqual(harness.presentationState.currentError, .invalidAPIKey)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "present_post_transcription_error")
        XCTAssertEqual(telemetry.metadata["operation"], "post_transcription")
        XCTAssertEqual(telemetry.metadata["error_type"], "invalid_api_key")
    }

    func testTranscriptPersistenceFailurePresenterPrefixesStatusAndOpensTranscript() throws {
        let harness = AppErrorPresenterHarness()
        let underlyingError = NSError(
            domain: "AppErrorPresenterTests",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "Disk locked"]
        )
        var showTranscriptCallCount = 0
        let presenter = TranscriptPersistenceFailurePresenter(
            errorPresenter: harness.presenter,
            showTranscriptWindow: {
                showTranscriptCallCount += 1
            }
        )

        presenter.present(underlyingError, sessionID: UUID())

        let appError = AppError.storageFailure("Disk locked")
        XCTAssertEqual(harness.presentationState.status, .error("Transcript ready, but \(appError.userMessage)"))
        XCTAssertEqual(harness.presentationState.currentError, appError)
        XCTAssertEqual(showTranscriptCallCount, 1)

        let telemetry = try harness.lastAppErrorTelemetry()
        XCTAssertEqual(telemetry.metadata["context"], "transcript_persist_failed")
        XCTAssertEqual(telemetry.metadata["operation"], "session_library")
        XCTAssertEqual(telemetry.metadata["error_type"], "storage_failure")
        XCTAssertEqual(telemetry.metadata["underlying_error"], "Disk locked")
    }
}

@MainActor
private final class AppErrorPresenterHarness {
    let presentationState = AppPresentationState()
    let telemetryRecorder = MockOperationalTelemetryRecorder()
    let presenter: AppErrorPresenter

    init() {
        self.presenter = AppErrorPresenter(
            presentationState: presentationState,
            telemetryRecorder: telemetryRecorder
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
