import XCTest
@testable import BugNarrator

final class AppErrorTests: XCTestCase {
    func testMicrophonePermissionDeniedUsesSpecificStatusPresentation() {
        XCTAssertEqual(AppError.microphonePermissionDenied.statusTitle, "Microphone Access Needed")
        XCTAssertEqual(AppError.microphonePermissionDenied.recoveryHeadline, "Microphone access is blocked.")
    }

    func testMicrophonePermissionRestrictedUsesSpecificStatusPresentation() {
        XCTAssertEqual(AppError.microphonePermissionRestricted.statusTitle, "Microphone Access Restricted")
        XCTAssertEqual(AppError.microphonePermissionRestricted.recoveryHeadline, "Microphone access is restricted.")
    }

    func testMicrophoneUnavailableUsesSpecificStatusPresentation() {
        XCTAssertEqual(
            AppError.microphoneUnavailable("The selected microphone could not be opened.").statusTitle,
            "Microphone Unavailable"
        )
        XCTAssertEqual(
            AppError.microphoneUnavailable("The selected microphone could not be opened.").recoveryHeadline,
            "Audio capture is unavailable."
        )
    }

    func testScreenRecordingPermissionDeniedUsesSpecificStatusPresentation() {
        XCTAssertEqual(AppError.screenRecordingPermissionDenied.statusTitle, "Screen Recording Access Needed")
        XCTAssertEqual(AppError.screenRecordingPermissionDenied.recoveryHeadline, "Screen recording access is blocked.")
    }

    func testSystemAudioUnavailableUsesSystemAudioRecoveryPresentation() {
        let error = AppError.systemAudioUnavailable("No audio frames were captured.")

        XCTAssertEqual(error.statusTitle, "System Audio Unavailable")
        XCTAssertEqual(error.recoveryHeadline, "System audio capture is unavailable.")
        XCTAssertTrue(error.suggestsSystemAudioPrivacySettings)
    }

    func testStorageFailureGivesActionableRecoveryGuidance() {
        let error = AppError.storageFailure("Disk full")

        XCTAssertEqual(
            error.userMessage,
            "Could not save local session history. The transcript is still in memory — copy it now from the popover before trying again. Details: Disk full"
        )
        XCTAssertEqual(
            error.recoveryHeadline,
            "BugNarrator could not save the session. Copy your transcript before retrying."
        )
    }

    func testOpenAIKeyErrorsUseSpecificStatusPresentation() {
        XCTAssertEqual(AppError.missingAPIKey.statusTitle, "OpenAI Key Needed")
        XCTAssertEqual(AppError.invalidAPIKey.statusTitle, "OpenAI Key Rejected")
        XCTAssertEqual(AppError.revokedAPIKey.statusTitle, "OpenAI Key Rejected")
    }

    func testParakeetSetupErrorsUseProviderSpecificStatusPresentation() {
        XCTAssertEqual(AppError.missingAPIKey.statusTitle(for: .parakeetLocal), "Local Parakeet Setup Needed")
        XCTAssertEqual(AppError.invalidAPIKey.statusTitle(for: .parakeetLocal), "Local Parakeet Setup Rejected")
        XCTAssertEqual(
            AppError.missingAPIKey.recoveryHeadline(for: .parakeetLocal),
            "Finish the Local (Parakeet) setup before continuing."
        )
    }
}
