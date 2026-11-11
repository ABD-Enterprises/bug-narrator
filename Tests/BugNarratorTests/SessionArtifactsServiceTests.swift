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

    func testRemovalRefusesAnOutsideDirectoryReachedThroughAnIntermediateLink() throws {
        let manager = FileManager.default
        let base = makeTempDirectory()
        defer { try? manager.removeItem(at: base) }
        let root = base.appendingPathComponent("SessionAssets")
        let outside = base.appendingPathComponent("outside")
        let victim = outside.appendingPathComponent("synthetic-session")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: victim, withIntermediateDirectories: true)
        let sentinel = victim.appendingPathComponent("keep.txt")
        try Data("synthetic private fixture".utf8).write(to: sentinel)
        try manager.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: outside)
        let service = SessionArtifactsService(rootDirectoryURL: root)

        XCTAssertEqual(service.removeArtifactsDirectory(at: root.appendingPathComponent("alias/synthetic-session")),
                       .rejectedUnmanagedDirectory)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("synthetic private fixture".utf8))
    }

    func testRemovalRefusesALinkBackToTheStorageRoot() throws {
        let manager = FileManager.default
        let base = makeTempDirectory()
        defer { try? manager.removeItem(at: base) }
        let root = base.appendingPathComponent("SessionAssets")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let sentinel = root.appendingPathComponent("keep.txt")
        try Data("synthetic root fixture".utf8).write(to: sentinel)
        try manager.createSymbolicLink(at: root.appendingPathComponent("root-alias"), withDestinationURL: root)
        let service = SessionArtifactsService(rootDirectoryURL: root)

        XCTAssertEqual(service.removeArtifactsDirectory(at: root.appendingPathComponent("root-alias")),
                       .rejectedUnmanagedDirectory)
        XCTAssertTrue(manager.fileExists(atPath: sentinel.path))
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

    // MARK: - Honest deletion reporting (#960)

    /// The service used to swallow the error with `try?` and log
    /// "Removed a BugNarrator-managed artifacts directory" regardless, so a
    /// failed deletion produced a success log while the spec promises deletion
    /// removes managed screenshots.
    func testFailedRemovalIsReportedRatherThanLoggedAsSuccess() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer {
            try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: rootDirectoryURL.path)
            try? FileManager.default.removeItem(at: rootDirectoryURL)
        }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let managedDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectoryURL, withIntermediateDirectories: true)

        // Make the parent immutable so the child cannot be unlinked.
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: managedRootURL.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: managedRootURL.path) }

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)
        let outcome = service.removeArtifactsDirectory(at: managedDirectoryURL)

        guard case .failed = outcome else {
            return XCTFail("Expected a failure outcome, got \(outcome). The directory is still on disk.")
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: managedDirectoryURL.path),
            "Precondition: the removal really did fail."
        )
    }

    func testRemovalOutcomesDistinguishManagedMissingAndRejected() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let managedRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let managedDirectoryURL = managedRootURL.appendingPathComponent("session", isDirectory: true)
        let externalDirectoryURL = rootDirectoryURL.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createDirectory(at: managedDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDirectoryURL, withIntermediateDirectories: true)

        let service = SessionArtifactsService(rootDirectoryURL: managedRootURL)

        XCTAssertEqual(service.removeArtifactsDirectory(at: managedDirectoryURL), .removed)
        XCTAssertEqual(service.removeArtifactsDirectory(at: managedDirectoryURL), .nothingToRemove)
        XCTAssertEqual(
            service.removeArtifactsDirectory(at: externalDirectoryURL),
            .rejectedUnmanagedDirectory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalDirectoryURL.path))
    }

}
