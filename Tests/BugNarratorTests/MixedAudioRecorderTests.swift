import AVFoundation
import XCTest
@testable import BugNarrator

@MainActor
final class MixedAudioRecorderTests: XCTestCase {
    func testTrackInsertionOffsetsDelayLaterMicrophoneStart() {
        let offsets = MixedAudioTrackInsertionOffsets(
            microphoneStartedAt: 42.150,
            systemAudioStartedAt: 42.000
        )

        XCTAssertEqual(offsets.systemAudioOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(offsets.microphoneOffset, 0.150, accuracy: 0.000_001)
        XCTAssertEqual(offsets.systemAudioInsertionTime.seconds, 0, accuracy: 0.000_001)
        XCTAssertEqual(offsets.microphoneInsertionTime.seconds, 0.150, accuracy: 0.000_01)
    }

    func testTrackInsertionOffsetsDelayLaterSystemAudioStart() {
        let offsets = MixedAudioTrackInsertionOffsets(
            microphoneStartedAt: 10.000,
            systemAudioStartedAt: 10.080
        )

        XCTAssertEqual(offsets.microphoneOffset, 0, accuracy: 0.000_001)
        XCTAssertEqual(offsets.systemAudioOffset, 0.080, accuracy: 0.000_001)
        XCTAssertEqual(offsets.microphoneInsertionTime.seconds, 0, accuracy: 0.000_001)
        XCTAssertEqual(offsets.systemAudioInsertionTime.seconds, 0.080, accuracy: 0.000_001)
    }

    func testStopRecordingRemovesSourceFilesAfterSuccessfulMix() async throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let microphoneURL = rootDirectoryURL.appendingPathComponent("microphone.wav")
        let systemAudioURL = rootDirectoryURL.appendingPathComponent("system.wav")
        try writeSilentAudioFile(to: microphoneURL)
        try writeSilentAudioFile(to: systemAudioURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.stopResults = [
            .success(RecordedAudio(fileURL: microphoneURL, duration: 0.1))
        ]
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.stopResults = [
            .success(RecordedAudio(fileURL: systemAudioURL, duration: 0.1))
        ]
        let recorder = MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            outputDirectoryURL: rootDirectoryURL
        )

        try await recorder.startRecording()
        let mixedAudio = try await recorder.stopRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: mixedAudio.fileURL.path))
        XCTAssertEqual(mixedAudio.fileURL.pathExtension, "m4a")
        XCTAssertFalse(FileManager.default.fileExists(atPath: microphoneURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemAudioURL.path))
    }

    func testStopRecordingRemovesMicrophoneFileWhenSystemAudioStopFails() async throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let microphoneURL = rootDirectoryURL.appendingPathComponent("microphone.wav")
        try writeSilentAudioFile(to: microphoneURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.stopResults = [
            .success(RecordedAudio(fileURL: microphoneURL, duration: 0.1))
        ]
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.stopResults = [
            .failure(AppError.recordingFailure("System audio failed to stop."))
        ]
        let recorder = MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            outputDirectoryURL: rootDirectoryURL
        )

        try await recorder.startRecording()
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected stop to throw when system audio failed.")
        } catch {
            // Expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: microphoneURL.path))
    }

    func testStopRecordingLeavesNoMixOutputBehindWhenMixingFails() async throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let corruptURL = rootDirectoryURL.appendingPathComponent("corrupt.wav")
        try Data("not audio".utf8).write(to: corruptURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.stopResults = [
            .success(RecordedAudio(fileURL: corruptURL, duration: 0.1))
        ]
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.stopResults = [
            .success(RecordedAudio(fileURL: corruptURL, duration: 0.1))
        ]
        let recorder = MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            outputDirectoryURL: rootDirectoryURL
        )

        try await recorder.startRecording()
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected mixed recording stop to throw on a corrupt source.")
        } catch {
            // Expected — mixing should not succeed on a corrupt source.
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: rootDirectoryURL,
            includingPropertiesForKeys: nil
        )
        let leftoverMixFiles = contents.filter { $0.pathExtension == "m4a" }
        XCTAssertTrue(
            leftoverMixFiles.isEmpty,
            "Expected no mixed-recording artifact after a failed stop, found: \(leftoverMixFiles)"
        )
    }

    func testStopRecordingRemovesSystemAudioFileWhenMicrophoneStopFails() async throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let systemAudioURL = rootDirectoryURL.appendingPathComponent("system.wav")
        try writeSilentAudioFile(to: systemAudioURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.stopResults = [
            .failure(AppError.recordingFailure("Microphone failed to stop."))
        ]
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.stopResults = [
            .success(RecordedAudio(fileURL: systemAudioURL, duration: 0.1))
        ]
        let recorder = MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            outputDirectoryURL: rootDirectoryURL
        )

        try await recorder.startRecording()
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected stop to throw when microphone failed.")
        } catch {
            // Expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: systemAudioURL.path))
    }

    func testStopRecordingStartsBothSourceStopsBeforeEitherCompletes() async throws {
        let rootDirectoryURL = temporaryDirectoryURL()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let microphoneURL = rootDirectoryURL.appendingPathComponent("microphone.wav")
        let systemAudioURL = rootDirectoryURL.appendingPathComponent("system.wav")
        try writeSilentAudioFile(to: microphoneURL)
        try writeSilentAudioFile(to: systemAudioURL)

        let microphoneRecorder = MockAudioRecorder()
        microphoneRecorder.suspendStop = true
        let systemAudioRecorder = MockAudioRecorder()
        systemAudioRecorder.suspendStop = true
        let recorder = MixedAudioRecorder(
            microphoneRecorder: microphoneRecorder,
            systemAudioRecorder: systemAudioRecorder,
            outputDirectoryURL: rootDirectoryURL
        )

        try await recorder.startRecording()
        let stopTask = Task {
            try await recorder.stopRecording()
        }

        await waitForStopCalls(microphoneRecorder: microphoneRecorder, systemAudioRecorder: systemAudioRecorder)

        XCTAssertEqual(microphoneRecorder.stopCallCount, 1)
        XCTAssertEqual(systemAudioRecorder.stopCallCount, 1)

        microphoneRecorder.resumeStop(with: .success(RecordedAudio(fileURL: microphoneURL, duration: 0.1)))
        systemAudioRecorder.resumeStop(with: .success(RecordedAudio(fileURL: systemAudioURL, duration: 0.1)))

        let mixedAudio = try await stopTask.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: mixedAudio.fileURL.path))
    }

    private func temporaryDirectoryURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSilentAudioFile(to url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        try file.write(from: buffer)
    }

    private func waitForStopCalls(
        microphoneRecorder: MockAudioRecorder,
        systemAudioRecorder: MockAudioRecorder,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if microphoneRecorder.stopCallCount == 1, systemAudioRecorder.stopCallCount == 1 {
                return
            }

            await Task.yield()
        }

        XCTFail(
            "Expected both mixed recorder sources to begin stopping.",
            file: file,
            line: line
        )
    }
}
