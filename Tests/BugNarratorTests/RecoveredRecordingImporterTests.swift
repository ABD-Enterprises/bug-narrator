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

    func testImporterCreatesRetryablePendingSessionForRecoveredSystemAudioWAV() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        let audioURL = recoveryDirectoryURL.appendingPathComponent("crash-recovery-system-audio.wav")
        try Data("system audio".utf8).write(to: audioURL)

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 1)

        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.pendingTranscription?.failureReason, .crashRecovery)
        XCTAssertEqual(session.pendingTranscription?.audioFileName, "recording.wav")
        XCTAssertEqual(session.pendingTranscription?.recoveredSourceFileName, audioURL.lastPathComponent)
        XCTAssertEqual(session.recoveredSourceFileName, audioURL.lastPathComponent)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: try XCTUnwrap(session.pendingTranscriptionAudioURL).path
            )
        )
    }

    func testImporterIgnoresUnsupportedRecoveredFiles() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        try Data("not audio".utf8).write(to: recoveryDirectoryURL.appendingPathComponent("notes.txt"))
        try Data("not supported".utf8).write(to: recoveryDirectoryURL.appendingPathComponent("recording.mp3"))

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 0)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testImporterIgnoresEmptyRecoveredAudioFiles() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        try Data().write(to: recoveryDirectoryURL.appendingPathComponent("empty-microphone.m4a"))
        try Data().write(to: recoveryDirectoryURL.appendingPathComponent("empty-system-audio.wav"))

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 0)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testImporterIgnoresRecoveredAudioDirectories() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: recoveryDirectoryURL.appendingPathComponent("directory-microphone.m4a", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: recoveryDirectoryURL.appendingPathComponent("directory-system-audio.wav", isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let artifactsService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(try importer.importRecoverableRecordings(into: store, artifactsService: artifactsService), 0)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testImporterContinuesAfterPerFileFailureAndCleansOrphanArtifacts() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let recoveryDirectoryURL = rootDirectoryURL.appendingPathComponent("RecoveredRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectoryURL, withIntermediateDirectories: true)

        let firstAudioURL = recoveryDirectoryURL.appendingPathComponent("first-recording.m4a")
        let secondAudioURL = recoveryDirectoryURL.appendingPathComponent("second-recording.m4a")
        try Data("first".utf8).write(to: firstAudioURL)
        try Data("second".utf8).write(to: secondAudioURL)
        let attributes: [FileAttributeKey: Any] = [.modificationDate: Date(timeIntervalSinceNow: -60)]
        try FileManager.default.setAttributes(attributes, ofItemAtPath: secondAudioURL.path)

        let store = TranscriptStore(storageURL: rootDirectoryURL.appendingPathComponent("sessions.json"))
        let underlyingService = MockArtifactsService(rootDirectoryURL: rootDirectoryURL.appendingPathComponent("artifacts"))
        let failingService = FailFirstArtifactsService(underlying: underlyingService)
        let importer = RecoveredRecordingImporter(recoveryDirectoryURL: recoveryDirectoryURL)

        XCTAssertEqual(
            try importer.importRecoverableRecordings(into: store, artifactsService: failingService),
            1
        )
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.recoveredSourceFileName, "second-recording.m4a")
        XCTAssertEqual(failingService.createCallCount, 2)
        XCTAssertEqual(underlyingService.createdDirectories.count, 1)
    }

    private func makeTempDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-RecoveredRecordingImporterTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}

private final class FailFirstArtifactsService: SessionArtifactsManaging {
    private let underlying: MockArtifactsService
    private(set) var createCallCount = 0

    init(underlying: MockArtifactsService) {
        self.underlying = underlying
    }

    func createArtifactsDirectory(for sessionID: UUID) throws -> URL {
        createCallCount += 1
        if createCallCount == 1 {
            throw NSError(
                domain: "FailFirstArtifactsService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated artifacts directory failure."]
            )
        }
        return try underlying.createArtifactsDirectory(for: sessionID)
    }

    func makeRecordedAudioURL(in directoryURL: URL, sourceFileURL: URL) -> URL {
        underlying.makeRecordedAudioURL(in: directoryURL, sourceFileURL: sourceFileURL)
    }

    func makeScreenshotURL(in directoryURL: URL, prefix: String, index: Int, elapsedTime: TimeInterval) -> URL {
        underlying.makeScreenshotURL(in: directoryURL, prefix: prefix, index: index, elapsedTime: elapsedTime)
    }

    func removeArtifactsDirectory(at directoryURL: URL) {
        underlying.removeArtifactsDirectory(at: directoryURL)
    }
}
