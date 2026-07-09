import AVFoundation
import XCTest
@testable import BugNarrator

/// Focused, permission-free coverage of the `SystemAudioFileWriter` lifecycle
/// extracted from `SystemAudioRecorder` (#435 slice 435b). None of these tests
/// touch CoreAudio or require system-audio permission — they exercise the
/// AVAudioFile finalize/close contract with an in-memory format and temp files.
final class SystemAudioFileWriterTests: XCTestCase {
    private func makeFormat() throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2))
    }

    private func makeTempURL(ext: String = "wav") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("system-audio-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    func testInitCreatesReadableAudioFile() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        try writer.close()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        // The finalized file is a readable audio file.
        XCTAssertNoThrow(try AVAudioFile(forReading: fileURL))
    }

    func testCloseWithoutWritesOrInvalidationDoesNotThrow() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        XCTAssertNoThrow(try writer.close())
    }

    func testZeroFrameSystemAudioFileSurfacesSystemAudioRecoveryGuidance() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        try writer.close()

        XCTAssertThrowsError(try SystemAudioRecorder.validateRecordedAudioFileSynchronously(at: fileURL)) { error in
            guard case let AppError.systemAudioUnavailable(message) = error else {
                return XCTFail("Expected systemAudioUnavailable, got \(error).")
            }

            XCTAssertTrue(message.contains("produced no audio frames"))
            XCTAssertTrue(message.contains("Audio Source to Mic only"))
            XCTAssertTrue(message.contains("Screen & System Audio Recording"))
        }
    }

    func testMarkFormatInvalidatedThenCloseThrowsRecordingFailure() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        writer.markFormatInvalidated()

        XCTAssertThrowsError(try writer.close()) { error in
            guard case let AppError.recordingFailure(message) = error else {
                return XCTFail("Expected recordingFailure, got \(error).")
            }
            XCTAssertTrue(message.contains("System audio format changed while recording"))
        }
    }

    func testSecondCloseAfterCleanCloseDoesNotThrow() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        try writer.close()
        // close() releases the handle and resets flags, so a second close() is
        // a safe no-op rather than a re-throw.
        XCTAssertNoThrow(try writer.close())
    }

    func testSecondCloseAfterFormatInvalidatedDoesNotRethrow() throws {
        let fileURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        writer.markFormatInvalidated()
        XCTAssertThrowsError(try writer.close())
        // The invalidated flag was reset during the first close(), so the second
        // close() must not throw again.
        XCTAssertNoThrow(try writer.close())
    }

    func testInitWithNonexistentParentDirectoryThrows() throws {
        // A destination under a directory that does not exist must fail at init
        // rather than returning a half-built writer. Avoids chmod/permission
        // environment flakiness.
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("capture.wav")

        XCTAssertThrowsError(try SystemAudioFileWriter(fileURL: badURL, format: makeFormat()))
    }

    func testInitAndCloseWithUnicodeFilenameSucceeds() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("système-audio-🎙️-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let writer = try SystemAudioFileWriter(fileURL: fileURL, format: makeFormat())
        try writer.close()

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertNoThrow(try AVAudioFile(forReading: fileURL))
    }
}
