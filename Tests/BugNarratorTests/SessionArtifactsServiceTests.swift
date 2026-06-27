import Foundation
import XCTest
@testable import BugNarrator

final class SessionArtifactsServiceTests: XCTestCase {
    func testRemoveArtifactsDirectoryOnlyDeletesManagedDirectories() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let externalDirectoryURL = rootDirectoryURL.appendingPathComponent("External", isDirectory: true)
        let managedDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)

        try FileManager.default.createDirectory(at: managedDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDirectoryURL, withIntermediateDirectories: true)

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)
        service.removeArtifactsDirectory(at: managedDirectoryURL)
        service.removeArtifactsDirectory(at: externalDirectoryURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: managedDirectoryURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalDirectoryURL.path))
    }

    func testPreserveRecordedAudioCopiesIntoDirectoryAndLeavesSource() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let sessionDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = rootDirectoryURL.appendingPathComponent("temp-recording.m4a")
        try Data("audio-bytes".utf8).write(to: sourceURL)
        let recordedAudio = RecordedAudio(fileURL: sourceURL, duration: 12)

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)
        let preservedURL = try service.preserveRecordedAudio(recordedAudio, in: sessionDirectoryURL)

        XCTAssertEqual(preservedURL.deletingLastPathComponent().standardizedFileURL, sessionDirectoryURL.standardizedFileURL)
        XCTAssertEqual(preservedURL.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: preservedURL.path))
        // Source is left untouched — the caller decides when to remove the temp.
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertEqual(try Data(contentsOf: preservedURL), Data("audio-bytes".utf8))
    }

    func testPreserveRecordedAudioRejectsEmptySource() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let sessionDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)

        let sourceURL = rootDirectoryURL.appendingPathComponent("empty.m4a")
        try Data().write(to: sourceURL)
        let recordedAudio = RecordedAudio(fileURL: sourceURL, duration: 0)

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)
        XCTAssertThrowsError(try service.preserveRecordedAudio(recordedAudio, in: sessionDirectoryURL))
    }

    func testMakeScreenshotURLSanitizesPrefix() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let sessionDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectoryURL, withIntermediateDirectories: true)

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)
        let screenshotURL = service.makeScreenshotURL(
            in: sessionDirectoryURL,
            prefix: " Marker / Capture ? ",
            index: 3,
            elapsedTime: 14
        )

        XCTAssertEqual(screenshotURL.lastPathComponent, "marker-capture-3-00-14.png")
    }

    private func makeTempDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-SessionArtifactsTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
