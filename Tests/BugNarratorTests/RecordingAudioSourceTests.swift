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
}
