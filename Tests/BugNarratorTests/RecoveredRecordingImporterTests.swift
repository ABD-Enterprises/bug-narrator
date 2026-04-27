import XCTest
@testable import BugNarrator

@MainActor
final class RecoveredRecordingImporterTests: XCTestCase {
    func testImporterCreatesCompletedSessionWhenRecoveredTranscriptExists() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        let transcriptsDirectoryURL = recoveryDirectoryURL.appendingPathComponent("transcripts", isDirectory: true)
        try FileManager.default.createDirectory(at: transcriptsDirectoryURL, withIntermediateDirectories: true)
        let audioURL = recoveryDirectoryURL.appendingPathComponent("2026-04-27-0939-crash-recovery-recording.m4a")
        try Data("audio".utf8).write(to: audioURL)
        try Data("Recovered transcript text.".utf8).write(
            to: transcriptsDirectoryURL.appendingPathComponent("2026-04-27-0939-crash-recovery-recording.transcript.txt")
        )

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 1)
        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 0)

        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.transcript, "Recovered transcript text.")
        XCTAssertNil(session.pendingTranscription)
        XCTAssertEqual(session.recoveredSourceFileName, audioURL.lastPathComponent)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(session.artifactsDirectoryURL).appendingPathComponent("recording.m4a").path
            )
        )
    }

    func testImporterCreatesRetryablePendingSessionWhenTranscriptIsMissing() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        let audioURL = recoveryDirectoryURL.appendingPathComponent("crash-recovery-recording.m4a")
        try Data("audio".utf8).write(to: audioURL)

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 1)

        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .crashRecovery)
        XCTAssertEqual(session.pendingTranscription?.recoveredSourceFileName, audioURL.lastPathComponent)
        XCTAssertEqual(session.recoveredSourceFileName, audioURL.lastPathComponent)
        XCTAssertTrue(session.preview.contains("Recovered recording found"))
    }

    private func makeTempDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-RecoveredRecordingImporterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
