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

    func testMicrophoneLevelCalculatorReturnsZeroForSilentBuffer() throws {
        let buffer = try makePCMBuffer(samples: [0, 0, 0, 0])

        XCTAssertEqual(MicrophoneLevelCalculator.normalizedRMSLevel(for: buffer), 0, accuracy: 0.000_001)
    }

    func testMicrophoneLevelCalculatorNormalizesRMSLevel() throws {
        let buffer = try makePCMBuffer(samples: [0.25, -0.25, 0.25, -0.25])

        XCTAssertEqual(MicrophoneLevelCalculator.normalizedRMSLevel(for: buffer), 1, accuracy: 0.000_001)
    }

    private func makePCMBuffer(samples: [Float]) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)))
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for (index, sample) in samples.enumerated() {
            channel[index] = sample
        }

        return buffer
    }
}
