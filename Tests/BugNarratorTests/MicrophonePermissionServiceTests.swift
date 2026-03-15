import XCTest
@testable import BugNarrator

@MainActor
final class MicrophonePermissionServiceTests: XCTestCase {
    func testPreflightRequestsPermissionAndSucceedsWhenGranted() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .notDetermined
        recorder.requestedPermissionStates = [.authorized]
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(recorder.permissionRequestCallCount, 1)
    }

    func testPreflightReturnsNeedsUserActionWhenPermissionDenied() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .denied
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .needsUserAction(.microphonePermissionDenied))
    }

    func testPreflightReturnsBlockedWhenPermissionRestricted() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .restricted
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .blocked(.microphonePermissionRestricted))
    }

    func testPreflightReturnsFailureWhenRecorderPrerequisitesFail() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .authorized
        recorder.prerequisiteError = .microphoneUnavailable("The selected microphone could not be opened.")
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .failure(.microphoneUnavailable("The selected microphone could not be opened.")))
    }

    func testRecoveryGuidanceIncludesLocalTestingNoteForDerivedDataBuilds() {
        let recorder = MockAudioRecorder()
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let guidance = service.recoveryGuidance(
            for: .denied,
            runtimeEnvironment: AppRuntimeEnvironment(
                bundlePath: "/Users/deffenda/Library/Developer/Xcode/DerivedData/BugNarrator/Build/Products/Debug/BugNarrator.app"
            )
        )

        XCTAssertTrue(guidance.message.contains("System Settings > Privacy & Security > Microphone"))
        XCTAssertEqual(
            guidance.localTestingNote,
            "Local unsigned builds can need microphone approval again if you switch to a different app copy or rebuild into a new path. For steadier testing, keep launching the same app copy or use the signed DMG build."
        )
    }
}
