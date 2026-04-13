import XCTest
@testable import BugNarrator

final class MenuBarStatusPresentationTests: XCTestCase {
    func testMicrophoneErrorUsesRecoveryWidthAndAction() {
        let presentation = MenuBarStatusPresentation(
            status: .error(AppError.microphonePermissionDenied.userMessage),
            currentError: .microphonePermissionDenied
        )

        XCTAssertEqual(presentation.recoveryAction, .microphone)
        XCTAssertEqual(presentation.preferredWidth, 420)
    }

    func testMicrophoneUnavailableUsesRecoveryWidthAndAction() {
        let presentation = MenuBarStatusPresentation(
            status: .error(AppError.microphoneUnavailable("The selected microphone could not be opened.").userMessage),
            currentError: .microphoneUnavailable("The selected microphone could not be opened.")
        )

        XCTAssertEqual(presentation.recoveryAction, .microphone)
        XCTAssertEqual(presentation.preferredWidth, 420)
    }

    func testScreenRecordingErrorUsesRecoveryWidthAndAction() {
        let presentation = MenuBarStatusPresentation(
            status: .recording(AppError.screenRecordingPermissionDenied.userMessage),
            currentError: .screenRecordingPermissionDenied
        )

        XCTAssertEqual(presentation.recoveryAction, .screenRecording)
        XCTAssertEqual(presentation.preferredWidth, 420)
    }

    func testOpenAIErrorUsesSettingsRecoveryAction() {
        let presentation = MenuBarStatusPresentation(
            status: .error(AppError.invalidAPIKey.userMessage),
            currentError: .invalidAPIKey
        )

        XCTAssertEqual(presentation.recoveryAction, .openAI)
        XCTAssertEqual(presentation.preferredWidth, 420)
    }

    func testTranscribingStateExpandsWidthForLongRunningStatus() {
        let presentation = MenuBarStatusPresentation(
            status: .transcribing("Step 1 of 3: Uploading audio to OpenAI for transcription..."),
            currentError: nil
        )

        XCTAssertEqual(presentation.recoveryAction, .none)
        XCTAssertEqual(presentation.preferredWidth, 390)
    }

    func testDefaultIdleStateStaysCompact() {
        let presentation = MenuBarStatusPresentation(
            status: .idle(),
            currentError: nil
        )

        XCTAssertEqual(presentation.recoveryAction, .none)
        XCTAssertEqual(presentation.preferredWidth, 340)
    }
}
