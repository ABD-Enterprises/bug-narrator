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
        XCTAssertEqual(recorder.activationProbeCallCount, 0)
    }

    func testPreflightDoesNotOverrideDeniedPermissionEvenIfProbeCouldSucceed() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .denied
        recorder.activationProbeBehavior = .success
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .needsUserAction(.microphonePermissionDenied))
        XCTAssertEqual(recorder.activationProbeCallCount, 0)
    }

    func testPreflightReturnsFailureWhenGrantedPermissionStillCannotStartRecorder() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .authorized
        recorder.activationProbeBehavior = .error(.microphoneUnavailable("The selected microphone could not be opened."))
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .failure(.microphoneUnavailable("The selected microphone could not be opened.")))
        XCTAssertEqual(recorder.activationProbeCallCount, 1)
    }

    func testPreflightReturnsBlockedWhenPermissionRestricted() async {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .restricted
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let result = await service.preflightForRecordingStart(audioRecorder: recorder)

        XCTAssertEqual(result, .blocked(.microphonePermissionRestricted))
        XCTAssertEqual(recorder.activationProbeCallCount, 0)
    }

    func testCurrentStatusReturnsGrantedWhenPermissionIsAuthorized() {
        let recorder = MockAudioRecorder()
        recorder.permissionState = .authorized
        let service = MicrophonePermissionService(permissionAccess: recorder)

        XCTAssertEqual(service.currentStatus(), .granted)
    }

    func testRecoveryGuidanceIncludesCaptureSetupFailureState() {
        let recorder = MockAudioRecorder()
        let service = MicrophonePermissionService(permissionAccess: recorder)

        let guidance = service.recoveryGuidance(
            for: .captureSetupFailed,
            runtimeEnvironment: AppRuntimeEnvironment(bundlePath: "/Applications/BugNarrator.app")
        )

        XCTAssertEqual(guidance.headline, "Microphone capture could not start.")
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
            "Local unsigned builds can need microphone approval again if you switch to a different app copy or rebuild into a new path. If System Settings already shows BugNarrator enabled, quit any other BugNarrator copies and retest the same app bundle path or the signed DMG build."
        )
    }
}
