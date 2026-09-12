import Foundation
import XCTest
@testable import BugNarrator

final class TranscriptStoreTests: XCTestCase {
    func testFailedRecoveryRejectsMutationsAndPreservesBodiesUntilIndexesAreRestored() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        try TranscriptStore(storageURL: storage).add(session)
        let indexes = ["sessions.index.json", "sessions.index.backup.json"].map { root.appendingPathComponent($0) }
        let originalIndex = try Data(contentsOf: indexes[0])
        let body = root.appendingPathComponent("Sessions/\(session.id).json")
        let originalBody = try Data(contentsOf: body)
        let corrupt = Data("corrupt".utf8)
        for index in indexes { try corrupt.write(to: index) }
        var artifactRemovals = 0
        let store = TranscriptStore(storageURL: storage, artifactsRemover: { _ in
            artifactRemovals += 1
            return .removed
        })
        XCTAssertThrowsError(try store.add(makeSampleTranscriptSession(index: 2)))
        XCTAssertThrowsError(try store.removeSessions(withIDs: [session.id]))
        XCTAssertEqual(try Data(contentsOf: body), originalBody)
        for index in indexes { XCTAssertEqual(try Data(contentsOf: index), corrupt) }
        XCTAssertEqual(artifactRemovals, 0)
        XCTAssertEqual(store.lastLoadRecoveryEvent?.source, .failed)

        for index in indexes { try originalIndex.write(to: index) }
        let newSession = makeSampleTranscriptSession(index: 3)
        try store.add(newSession)
        XCTAssertEqual(Set(store.allStoredSessionIDs()), [session.id, newSession.id])
        XCTAssertEqual(store.session(with: session.id), session)
    }

    func testUnreadableBodyDirectoryDoesNotEnableWrites() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        try TranscriptStore(storageURL: storage).add(session)
        for name in ["sessions.index.json", "sessions.index.backup.json"] {
            try FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        let files = UnreadableSessionDirectoryFileManager()
        let store = TranscriptStore(fileManager: files, storageURL: storage)
        XCTAssertEqual(store.lastLoadRecoveryEvent?.source, .failed)
        files.denyEnumeration = false
        XCTAssertThrowsError(try store.add(makeSampleTranscriptSession(index: 2)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions/\(session.id).json").path))
    }

    func testOrphanedBodiesWithoutIndexesDoNotBecomeAnEmptyWritableStore() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        try TranscriptStore(storageURL: storage).add(session)
        for name in ["sessions.index.json", "sessions.index.backup.json"] {
            try FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        let store = TranscriptStore(storageURL: storage)
        XCTAssertThrowsError(try store.add(makeSampleTranscriptSession(index: 2)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions/\(session.id).json").path))
    }

    func testLegacyCopiesAreRetiredAndCannotResurrectDeletedSessions() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let backup = root.appendingPathComponent("sessions.backup.json")
        let session = makeSampleTranscriptSession(index: 1)
        let legacy = try JSONEncoder().encode([session])
        try legacy.write(to: storage)
        try legacy.write(to: backup)
        let store = TranscriptStore(storageURL: storage)
        XCTAssertEqual(store.session(with: session.id), session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
        try store.removeSessions(withIDs: [session.id])
        // Even a stale source restored externally must not cross the committed format boundary.
        try legacy.write(to: backup)
        for name in ["sessions.index.json", "sessions.index.backup.json"] {
            try Data("corrupt".utf8).write(to: root.appendingPathComponent(name))
        }
        let reloaded = TranscriptStore(storageURL: storage)
        XCTAssertTrue(reloaded.libraryEntries.isEmpty)
        XCTAssertEqual(reloaded.lastLoadRecoveryEvent?.source, .failed)
        XCTAssertThrowsError(try reloaded.add(makeSampleTranscriptSession(index: 2)))
    }

    func testStaleLegacyCannotResurrectAnEmptyPartitionedHistory() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        let store = TranscriptStore(storageURL: storage)
        try store.add(session)
        try store.removeSessions(withIDs: [session.id])
        try JSONEncoder().encode([session]).write(to: storage)
        for name in ["sessions.index.json", "sessions.index.backup.json"] {
            try Data("corrupt".utf8).write(to: root.appendingPathComponent(name))
        }
        let reloaded = TranscriptStore(storageURL: storage)
        XCTAssertTrue(reloaded.libraryEntries.isEmpty)
        XCTAssertEqual(reloaded.lastLoadRecoveryEvent?.source, .failed)
        XCTAssertThrowsError(try reloaded.add(makeSampleTranscriptSession(index: 2)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions/\(session.id).json").path))
    }

    func testStaleLegacyCannotReplaceUnreadablePartitionedHistory() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let older = makeSampleTranscriptSession(index: 1)
        let newer = makeSampleTranscriptSession(index: 2)
        let store = TranscriptStore(storageURL: storage)
        try store.add(older)
        try store.add(newer)
        let legacy = try JSONEncoder().encode([older])
        try legacy.write(to: storage)
        for name in ["sessions.index.json", "sessions.index.backup.json"] {
            try Data("corrupt".utf8).write(to: root.appendingPathComponent(name))
        }
        let reloaded = TranscriptStore(storageURL: storage)
        XCTAssertEqual(reloaded.lastLoadRecoveryEvent?.source, .failed)
        XCTAssertThrowsError(try reloaded.add(makeSampleTranscriptSession(index: 3)))
        XCTAssertEqual(try Data(contentsOf: storage), legacy)
        for session in [older, newer] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sessions/\(session.id).json").path))
        }
    }

    func testExistingPartitionedStoreRetiresLeftoverLegacyCopies() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        try TranscriptStore(storageURL: storage).add(session)
        try JSONEncoder().encode([session]).write(to: storage)
        // Older indexes used preview-only search metadata; it is not body identity.
        let indexURL = root.appendingPathComponent("sessions.index.json")
        var index = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any])
        var entries = try XCTUnwrap(index["entries"] as? [[String: Any]])
        entries[0]["searchIndexText"] = "old preview-only search text"
        index["entries"] = entries
        try JSONSerialization.data(withJSONObject: index).write(to: indexURL)
        try Data("corrupt".utf8).write(to: root.appendingPathComponent("sessions.index.backup.json"))
        let reloaded = TranscriptStore(storageURL: storage)
        XCTAssertEqual(reloaded.session(with: session.id), session)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path))
        try reloaded.add(makeSampleTranscriptSession(index: 2))
    }

    func testTranscriptStorePersistsSessionsAcrossReloads() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let keychain = MockKeychainService()
        let protector = KeychainSessionDataProtector(keychainService: keychain)
        let firstStore = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        let session = makeSampleTranscriptSession(index: 1)

        try firstStore.add(session)

        let secondStore = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        let sessionData = try Data(
            contentsOf: rootDirectoryURL
                .appendingPathComponent("Sessions", isDirectory: true)
                .appendingPathComponent(session.id.uuidString)
                .appendingPathExtension("json")
        )

        XCTAssertTrue(secondStore.sessions.isEmpty)
        XCTAssertEqual(secondStore.libraryEntries.map(\.id), [session.id])
        XCTAssertEqual(secondStore.session(with: session.id), session)
        XCTAssertNil(sessionData.range(of: Data("Transcript 1".utf8)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootDirectoryURL.appendingPathComponent("sessions.index.json").path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: rootDirectoryURL
                    .appendingPathComponent("Sessions", isDirectory: true)
                    .appendingPathComponent(session.id.uuidString)
                    .appendingPathExtension("json")
                    .path
            )
        )
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
        XCTAssertEqual(reloadedStore.libraryEntries.map(\.id), [secondSession.id])
        XCTAssertEqual(reloadedStore.session(with: secondSession.id), secondSession)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: rootDirectoryURL
                    .appendingPathComponent("Sessions", isDirectory: true)
                    .appendingPathComponent(firstSession.id.uuidString)
                    .appendingPathExtension("json")
                    .path
            )
        )
    }

    func testTranscriptStoreMigratesLegacyMonolithicSessionsOnLoad() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let session = makeSampleTranscriptSession(index: 1)
        let data = try JSONEncoder().encode([session])
        try data.write(to: storageURL, options: [.atomic])

        let store = TranscriptStore(storageURL: storageURL)

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.libraryEntries.map(\.id), [session.id])
        XCTAssertEqual(store.session(with: session.id), session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootDirectoryURL.appendingPathComponent("sessions.index.json").path))
    }

    func testTranscriptStoreReportsFailedRecoveryWhenPartitionedIndexIsCorrupt() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let store = TranscriptStore(storageURL: storageURL)
        try store.add(makeSampleTranscriptSession(index: 1))

        try Data("not-json".utf8).write(
            to: rootDirectoryURL.appendingPathComponent("sessions.index.json"),
            options: [.atomic]
        )
        try Data("not-json".utf8).write(
            to: rootDirectoryURL.appendingPathComponent("sessions.index.backup.json"),
            options: [.atomic]
        )

        let reloadedStore = TranscriptStore(storageURL: storageURL)

        XCTAssertTrue(reloadedStore.sessions.isEmpty)
        XCTAssertEqual(
            reloadedStore.lastLoadRecoveryEvent,
            TranscriptStoreRecoveryEvent(source: .failed, recoveredSessionCount: 0)
        )
    }

    func testTranscriptStoreRecoversFromBackupWhenPrimaryFileIsCorrupt() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let backupURL = storageURL.deletingPathExtension().appendingPathExtension("backup.json")
        let session = makeSampleTranscriptSession(index: 1)

        try Data("not-json".utf8).write(to: storageURL, options: [.atomic])
        try JSONEncoder().encode([session]).write(to: backupURL, options: [.atomic])

        let recoveredStore = TranscriptStore(storageURL: storageURL)

        XCTAssertTrue(recoveredStore.sessions.isEmpty)
        XCTAssertEqual(recoveredStore.libraryEntries.map(\.id), [session.id])
        XCTAssertEqual(recoveredStore.session(with: session.id), session)
        XCTAssertEqual(
            recoveredStore.lastLoadRecoveryEvent,
            TranscriptStoreRecoveryEvent(source: .backup, recoveredSessionCount: 1)
        )
    }

    func testTranscriptStoreStillSurfacesRecoveredSessionsWhenDurableRepairFails() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let backupURL = storageURL.deletingPathExtension().appendingPathExtension("backup.json")
        let session = makeSampleTranscriptSession(index: 1)

        try Data("not-json".utf8).write(to: storageURL, options: [.atomic])
        try JSONEncoder().encode([session]).write(to: backupURL, options: [.atomic])

        // Occupy the partitioned index path with a directory so the durable
        // repair write during recovery fails. Previously this was swallowed with
        // try?; now it is logged, but the recovered session must still be surfaced
        // (not silently lost) for the rest of the run.
        let indexURL = rootDirectoryURL.appendingPathComponent("sessions.index.json")
        try FileManager.default.createDirectory(at: indexURL, withIntermediateDirectories: true)

        let store = TranscriptStore(storageURL: storageURL)

        XCTAssertEqual(store.libraryEntries.map(\.id), [session.id])
        XCTAssertEqual(store.session(with: session.id), session)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertThrowsError(try store.removeSessions(withIDs: [session.id]))
        XCTAssertThrowsError(try store.add(makeSampleTranscriptSession(index: 2)))
        XCTAssertEqual(store.session(with: session.id), session)
        XCTAssertEqual(
            store.lastLoadRecoveryEvent,
            TranscriptStoreRecoveryEvent(source: .backup, recoveredSessionCount: 1)
        )
    }

    func testTranscriptStoreReportsFailedRecoveryWhenPrimaryAndBackupAreCorrupt() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let backupURL = storageURL.deletingPathExtension().appendingPathExtension("backup.json")
        try Data("not-json".utf8).write(to: storageURL, options: [.atomic])
        try Data("not-json".utf8).write(to: backupURL, options: [.atomic])

        let store = TranscriptStore(storageURL: storageURL)

        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(
            store.lastLoadRecoveryEvent,
            TranscriptStoreRecoveryEvent(source: .failed, recoveredSessionCount: 0)
        )
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
        let reloadedSession = try XCTUnwrap(reloadedStore.session(with: session.id))

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

    /// #957 put the full transcript into the library index so mid-session words
    /// are searchable. That is only acceptable because the index is protected
    /// at rest — a plaintext index would have traded a search bug for a much
    /// larger disclosure than the 160-character preview it used to leak.
    func testSessionIndexIsProtectedAtRestAndStillLoads() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let protector = KeychainSessionDataProtector(keychainService: MockKeychainService())
        let store = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)

        let secret = "the checkout button renders offscreen"
        try store.add(
            TranscriptSession(
                id: UUID(),
                createdAt: Date(timeIntervalSince1970: 1_000),
                transcript: String(repeating: "narrating steadily. ", count: 20) + secret,
                duration: 60,
                model: "whisper-1",
                languageHint: nil,
                prompt: nil
            )
        )

        let indexURL = rootDirectoryURL.appendingPathComponent("sessions.index.json")
        let indexData = try Data(contentsOf: indexURL)
        XCTAssertNil(
            indexData.range(of: Data(secret.utf8)),
            "The search index must not carry transcript text in the clear."
        )

        let reloaded = TranscriptStore(storageURL: storageURL, sessionDataProtector: protector)
        XCTAssertEqual(reloaded.libraryEntries.count, 1, "A protected index must still load.")
        XCTAssertTrue(
            reloaded.libraryEntries[0].searchIndexText.contains("offscreen"),
            "And it must still carry the full-transcript search text."
        )
    }


    /// #960: the 500-session retention cap dropped the oldest session's JSON but
    /// left its artifacts directory — screenshots and preserved audio — on disk
    /// with nothing referencing it, and told the user nothing.
    ///
    /// This drives the real eviction path (adding past the cap), not explicit
    /// deletion. Explicit deletion removes the session file before the orphan
    /// sweep runs, and already cleans artifacts via SessionLibraryController.
    func testRetentionEvictionRemovesArtifactsAndSurfacesTheCap() throws {
        let rootDirectoryURL = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: rootDirectoryURL) }

        let storageURL = rootDirectoryURL.appendingPathComponent("sessions.json")
        let artifactsRootURL = rootDirectoryURL.appendingPathComponent("SessionAssets", isDirectory: true)
        let artifactsService = SessionArtifactsService(rootDirectoryURL: artifactsRootURL)

        let store = TranscriptStore(
            storageURL: storageURL,
            artifactsRemover: { artifactsService.removeArtifactsDirectory(at: $0) }
        )

        // The oldest session owns an artifacts directory; it is the one the cap
        // will drop once we exceed 500.
        let evictedID = UUID()
        let evictedArtifactsURL = artifactsRootURL.appendingPathComponent(evictedID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: evictedArtifactsURL, withIntermediateDirectories: true)
        try Data("screenshot".utf8).write(to: evictedArtifactsURL.appendingPathComponent("shot.png"))

        try store.add(
            TranscriptSession(
                id: evictedID,
                createdAt: Date(timeIntervalSince1970: 1),
                transcript: "oldest",
                duration: 1,
                model: "whisper-1",
                languageHint: nil,
                prompt: nil,
                artifactsDirectoryPath: evictedArtifactsURL.path
            )
        )

        for index in 1...500 {
            try store.add(
                TranscriptSession(
                    id: UUID(),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index)),
                    transcript: "s\(index)",
                    duration: 1,
                    model: "whisper-1",
                    languageHint: nil,
                    prompt: nil
                )
            )
        }

        XCTAssertEqual(store.sessionCount, 500, "Precondition: the cap held.")
        XCTAssertNil(
            store.libraryEntries.first(where: { $0.id == evictedID }),
            "Precondition: the oldest session was the one evicted."
        )

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: evictedArtifactsURL.path),
            "Eviction must take the dropped session's screenshots and audio with it."
        )
        XCTAssertEqual(
            store.lastLoadRecoveryEvent?.source,
            .retentionEviction,
            "The cap must be visible to the user, not silent data loss."
        )
    }

}

private final class UnreadableSessionDirectoryFileManager: FileManager {
    var denyEnumeration = true

    override func contentsOfDirectory(atPath path: String) throws -> [String] {
        if denyEnumeration && URL(fileURLWithPath: path).lastPathComponent == "Sessions" {
            throw CocoaError(.fileReadNoPermission)
        }
        return try super.contentsOfDirectory(atPath: path)
    }
}
