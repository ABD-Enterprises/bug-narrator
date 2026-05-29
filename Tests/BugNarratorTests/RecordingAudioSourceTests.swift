import XCTest
@testable import BugNarrator

final class RecordingAudioSourceTests: XCTestCase {
    func testAllSourcesExposeStableTitlesAndDiagnosticsValues() {
        XCTAssertEqual(RecordingAudioSource.allCases, [.microphone, .systemAudio, .microphoneAndSystemAudio])
        XCTAssertEqual(RecordingAudioSource.microphone.title, "Mic only")
        XCTAssertEqual(RecordingAudioSource.systemAudio.title, "System audio only")
        XCTAssertEqual(RecordingAudioSource.microphoneAndSystemAudio.title, "Mic + system audio")
        XCTAssertEqual(RecordingAudioSource.microphone.diagnosticsValue, "microphone")
        XCTAssertEqual(RecordingAudioSource.systemAudio.id, "systemAudio")
    }

    func testSourceCapabilityFlagsMatchSelectedInputs() {
        XCTAssertTrue(RecordingAudioSource.microphone.usesMicrophone)
        XCTAssertFalse(RecordingAudioSource.microphone.usesSystemAudio)

        XCTAssertFalse(RecordingAudioSource.systemAudio.usesMicrophone)
        XCTAssertTrue(RecordingAudioSource.systemAudio.usesSystemAudio)

        XCTAssertTrue(RecordingAudioSource.microphoneAndSystemAudio.usesMicrophone)
        XCTAssertTrue(RecordingAudioSource.microphoneAndSystemAudio.usesSystemAudio)
    }

    func testSystemAudioAggregateDeviceIdentityOnlyMatchesBugNarratorOwnedDevices() {
        let ownedUID = "\(SystemAudioAggregateDeviceIdentity.uidPrefix)A3F3A4E8-8637-4596-B3A7-4DF4CC893C11"

        XCTAssertTrue(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID(ownedUID))
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("BugNarrator.Other.\(UUID().uuidString)"))
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID("com.apple.BugNarrator.SystemAudio.\(UUID().uuidString)"))
        XCTAssertFalse(SystemAudioAggregateDeviceIdentity.isOwnedAggregateDeviceUID(""))
    }
}
