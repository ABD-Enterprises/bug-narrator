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

    func testMicAndSystemAudioRequiresFeatureFlag() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.recordingAudioSource = .microphoneAndSystemAudio
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: MockAudioRecorder(),
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        let error = await router.validateRecordingActivation()

        XCTAssertEqual(error, .systemAudioFeatureDisabled)
    }

    func testMicAndSystemAudioRequiresConsentAcknowledgement() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .microphoneAndSystemAudio
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: MockAudioRecorder(),
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        let error = await router.validateRecordingActivation()

        XCTAssertEqual(error, .systemAudioConsentRequired)
    }

    func testMicrophoneOnlySkipsSystemAudioReadiness() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.recordingAudioSource = .microphone
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: MockAudioRecorder(),
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        let error = await router.validateRecordingActivation()

        XCTAssertNil(error)
    }

    func testStartRecordingSurfacesReadinessErrorBeforeInvokingSourceRecorder() async {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .systemAudio

        let systemRecorder = MockAudioRecorder()
        systemRecorder.requiresMicrophonePermission = false
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: MockAudioRecorder(),
            systemAudioRecorder: systemRecorder,
            microphoneAndSystemAudioRecorder: MockAudioRecorder()
        )

        do {
            try await router.startRecording()
            XCTFail("Expected startRecording to throw .systemAudioConsentRequired.")
        } catch let error as AppError {
            XCTAssertEqual(error, .systemAudioConsentRequired)
        } catch {
            XCTFail("Expected AppError, got \(error).")
        }

        XCTAssertEqual(systemRecorder.startCallCount, 0)
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

    func testDefaultMixedRecorderUsesInjectedSourceRecorders() async throws {
        let (store, defaults, defaultsSuiteName) = makeSettingsStore()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName) }
        store.systemAudioCaptureEnabled = true
        store.recordingAudioSource = .microphoneAndSystemAudio
        store.hasAcceptedSystemAudioRecordingConsent = true

        let rootDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }
        try FileManager.default.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)

        let microphoneURL = rootDirectoryURL.appendingPathComponent("microphone.wav")
        let systemAudioURL = rootDirectoryURL.appendingPathComponent("system.wav")
        try Data("not real audio".utf8).write(to: microphoneURL)
        try Data("not real audio".utf8).write(to: systemAudioURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.stopResults = [
            .success(RecordedAudio(fileURL: microphoneURL, duration: 0.1))
        ]
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.requiresMicrophonePermission = false
        systemAudioRecorder.stopResults = [
            .success(RecordedAudio(fileURL: systemAudioURL, duration: 0.1))
        ]
        let router = RoutingAudioRecorder(
            settingsStore: store,
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder
        )

        try await router.startRecording()
        do {
            _ = try await router.stopRecording()
            XCTFail("Expected mixed stop to fail while proving the injected source recorders were used.")
        } catch {
            // Expected: the injected recorders returned intentionally invalid audio files.
        }

        XCTAssertEqual(microphoneRecorder.startCallCount, 1)
        XCTAssertEqual(microphoneRecorder.stopCallCount, 1)
        XCTAssertEqual(systemAudioRecorder.startCallCount, 1)
        XCTAssertEqual(systemAudioRecorder.stopCallCount, 1)
    }

    private func makeSettingsStore() -> (SettingsStore, UserDefaults, String) {
        let suiteName = "BugNarrator-RoutingAudioRecorderTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: defaults, keychainService: MockKeychainService())
        return (store, defaults, suiteName)
    }
}
