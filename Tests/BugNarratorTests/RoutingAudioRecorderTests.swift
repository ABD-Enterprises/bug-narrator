import XCTest
@testable import BugNarrator

@MainActor
final class RoutingAudioRecorderTests: XCTestCase {
    func testSystemAudioRequiresFeatureFlag() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.recordingAudioSource = .systemAudio
        let systemRecorder = MockAudioRecorder()
        systemRecorder.requiresMicrophonePermission = false
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: systemRecorder,
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        let error = await router.validateRecordingActivation()

        XCTAssertEqual(error, .systemAudioFeatureDisabled)
        XCTAssertFalse(router.requiresMicrophonePermission)
    }

    func testSystemAudioRequiresConsentAcknowledgement() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .systemAudio
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: MockAudioRecorder(),
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        let error = await router.validateRecordingActivation()

        XCTAssertEqual(error, .systemAudioConsentRequired)
    }

    func testRoutesSystemAudioStartAndStopToSystemRecorder() async throws {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .systemAudio
        store.hasAcceptedSystemAudioRecordingConsent = true

        let microphoneRecorder = MockAudioRecorder()
        let systemRecorder = MockAudioRecorder()
        systemRecorder.requiresMicrophonePermission = false
        systemRecorder.stopResults = [
            .success(RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/system.wav"), duration: 3))
        ]
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemRecorder,
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        try await router.startRecording()
        let recordedAudio = try await router.stopRecording()

        XCTAssertEqual(recordedAudio.fileURL.lastPathComponent, "system.wav")
        XCTAssertEqual(systemRecorder.startCallCount, 1)
        XCTAssertEqual(systemRecorder.stopCallCount, 1)
        XCTAssertEqual(microphoneRecorder.startCallCount, 0)
    }

    func testRoutesMicAndSystemModeToMixedRecorderAndRequiresMicrophonePermission() async throws {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .microphoneAndSystemAudio
        store.hasAcceptedSystemAudioRecordingConsent = true

        let mixedRecorder = MockAudioRecorder()
        mixedRecorder.stopResults = [
            .success(RecordedAudio(fileURL: URL(fileURLWithPath: "/tmp/mixed.m4a"), duration: 5))
        ]
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: MockAudioRecorder(),
            microphoneAndSystemAudioRecorder: mixedRecorder
        )

        try await router.startRecording()
        let recordedAudio = try await router.stopRecording()

        XCTAssertTrue(router.requiresMicrophonePermission)
        XCTAssertEqual(recordedAudio.fileURL.lastPathComponent, "mixed.m4a")
        XCTAssertEqual(mixedRecorder.startCallCount, 1)
        XCTAssertEqual(mixedRecorder.stopCallCount, 1)
    }

    private func makeSettingsStore() -> (SettingsStore, UserDefaults, String) {
        let suiteName = "BugNarrator-RoutingAudioRecorderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        return (store, defaults, suiteName)
    }
}
