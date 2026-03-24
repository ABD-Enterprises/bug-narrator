import Foundation
import XCTest
@testable import BugNarrator

final class TranscriptStoreTests: XCTestCase {
    func testTranscriptStorePersistsSessionsAcrossReloads() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let firstStore = TranscriptStore(storageURL: storageURL)
        let session = makeSampleTranscriptSession(index: 1)

        try firstStore.add(session)

        let secondStore = TranscriptStore(storageURL: storageURL)

        XCTAssertEqual(secondStore.sessions, [session])
    }

    func testTranscriptStoreKeepsMostRecentFiveHundredSessions() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)

        for index in 0..<505 {
            try store.add(makeSampleTranscriptSession(index: index))
        }

        XCTAssertEqual(store.sessions.count, 500)
        XCTAssertEqual(store.sessions.first?.transcript, "Transcript 504")
        XCTAssertEqual(store.sessions.last?.transcript, "Transcript 5")
    }

    func testTranscriptStoreRemovesSessionsAndPersistsDeletion() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let firstSession = makeSampleTranscriptSession(index: 1)
        let secondSession = makeSampleTranscriptSession(index: 2)

        try store.add(firstSession)
        try store.add(secondSession)

        let removedSessions = try store.removeSessions(withIDs: [firstSession.id])
        let reloadedStore = TranscriptStore(storageURL: storageURL)

        XCTAssertEqual(removedSessions, [firstSession])
        XCTAssertEqual(reloadedStore.sessions, [secondSession])
    }

    func testTranscriptStoreRollsBackInMemoryAddWhenPersistFails() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let firstSession = makeSampleTranscriptSession(index: 1)
        let secondSession = makeSampleTranscriptSession(index: 2)

        try store.add(firstSession)
        try FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.add(secondSession))
        XCTAssertEqual(store.sessions, [firstSession])
    }

    func testTranscriptStoreRollsBackRemovalWhenPersistFails() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let firstSession = makeSampleTranscriptSession(index: 1)
        let secondSession = makeSampleTranscriptSession(index: 2)

        try store.add(firstSession)
        try store.add(secondSession)
        try FileManager.default.removeItem(at: storageURL)
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try store.removeSessions(withIDs: [firstSession.id]))
        XCTAssertEqual(store.sessions, [secondSession, firstSession])
    }

    func testTranscriptStoreRecoversFromBackupWhenPrimaryFileIsCorrupt() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let session = makeSampleTranscriptSession(index: 1)

        try store.add(session)
        try Data("not-json".utf8).write(to: storageURL, options: [.atomic])

        let recoveredStore = TranscriptStore(storageURL: storageURL)

        XCTAssertEqual(recoveredStore.sessions, [session])
    }

    func testTranscriptStoreUpdatesLookupAndLibraryEntriesTogether() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        var session = makeSampleTranscriptSession(index: 1)

        try store.add(session)

        XCTAssertEqual(store.session(with: session.id), session)
        XCTAssertEqual(store.libraryEntries.first?.id, session.id)
        XCTAssertEqual(store.libraryEntries.first?.title, session.title)

        session.issueExtraction = IssueExtractionResult(summary: "Updated summary", issues: [])
        try store.add(session)

        XCTAssertEqual(store.session(with: session.id)?.summaryText, "Updated summary")
        XCTAssertEqual(store.libraryEntries.first?.summaryText, "Updated summary")
    }

    func testTranscriptStorePersistsPendingTranscriptionMetadataAcrossReloads() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let session = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            transcript: "",
            duration: 12,
            model: "gpt-4o-transcribe",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: PendingTranscription(
                audioFileName: "recording.m4a",
                failureReason: .missingAPIKey,
                preservedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
            artifactsDirectoryPath: "/tmp/bugnarrator/session-1"
        )

        try store.add(session)

        let reloadedStore = TranscriptStore(storageURL: storageURL)
        let reloadedSession = try XCTUnwrap(reloadedStore.sessions.first)

        XCTAssertEqual(reloadedSession.pendingTranscription?.audioFileName, "recording.m4a")
        XCTAssertEqual(reloadedStore.libraryEntries.first?.isPendingTranscription, true)
    }

    func testTranscriptStoreTracksPendingTranscriptionSessionsForRecoverySurfacing() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        let completedSession = makeSampleTranscriptSession(index: 1)
        let pendingSession = TranscriptSession(
            createdAt: Date(timeIntervalSince1970: 1_700_000_500),
            transcript: "",
            duration: 18,
            model: "gpt-4o-transcribe",
            languageHint: nil,
            prompt: nil,
            pendingTranscription: PendingTranscription(
                audioFileName: "recording.m4a",
                failureReason: .missingAPIKey,
                preservedAt: Date(timeIntervalSince1970: 1_700_000_600)
            ),
            artifactsDirectoryPath: "/tmp/bugnarrator/session-pending"
        )

        try store.add(completedSession)
        try store.add(pendingSession)

        XCTAssertEqual(store.pendingTranscriptionSessionCount, 1)
        XCTAssertEqual(store.latestPendingTranscriptionSession?.id, pendingSession.id)
    }

    private func makeTempDirectory() -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BugNarrator-TranscriptStoreTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
