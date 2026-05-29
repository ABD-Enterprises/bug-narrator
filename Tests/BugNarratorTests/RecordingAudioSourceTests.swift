import AVFoundation
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

    func testSystemAudioFileWriterFailsCloseWhenFormatInvalidated() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("system-audio-format-invalidated-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: format)

        writer.markFormatInvalidated()

        XCTAssertThrowsError(try writer.close()) { error in
            guard case let AppError.recordingFailure(message) = error else {
                XCTFail("Expected recordingFailure, got \(error).")
                return
            }

            XCTAssertTrue(message.contains("System audio format changed while recording"))
        }
    }
}
