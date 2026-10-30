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

    func testProviderSetupErrorUsesSettingsRecoveryAction() {
        let presentation = MenuBarStatusPresentation(
            status: .error(AppError.invalidAPIKey.userMessage),
            currentError: .invalidAPIKey
        )

        XCTAssertEqual(presentation.recoveryAction, .providerSettings)
        XCTAssertEqual(presentation.preferredWidth, 420)
    }

    func testExportConfigurationErrorUsesSettingsRecoveryAction() {
        // An export that is refused because its configuration is unsafe has to
        // point at the settings the user has to change.
        for error in [
            AppError.exportConfigurationMissing("The Jira site is not configured."),
            AppError.exportConfigurationIncompatible("The Jira base URL uses plaintext HTTP to a remote host.")
        ] {
            let presentation = MenuBarStatusPresentation(
                status: .error(error.userMessage),
                currentError: error
            )

            XCTAssertEqual(presentation.recoveryAction, .exportConfiguration)
            XCTAssertEqual(presentation.preferredWidth, 420)
        }
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
