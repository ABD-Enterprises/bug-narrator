import Foundation

final class TranscriptStore: ObservableObject {
    @Published private(set) var sessions: [TranscriptSession] = []
    @Published private(set) var libraryEntries: [SessionLibraryEntry] = []
    @Published private(set) var lastLoadRecoveryEvent: TranscriptStoreRecoveryEvent?
    private let logger = DiagnosticsLogger(category: .sessionLibrary)

    var pendingTranscriptionSessions: [TranscriptSession] {
        libraryEntries
            .filter(\.isPendingTranscription)
            .compactMap { session(with: $0.id) }
    }

    var pendingTranscriptionSessionCount: Int {
        libraryEntries.filter(\.isPendingTranscription).count
    }

    var latestPendingTranscriptionSession: TranscriptSession? {
        guard let pendingEntry = libraryEntries.first(where: \.isPendingTranscription) else {
            return nil
        }
        return session(with: pendingEntry.id)
    }

    var sessionCount: Int {
        libraryEntries.count
    }

    private enum StoragePolicy {
        static let maximumStoredSessions = 500
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageURL: URL
    private let backupStorageURL: URL
    private let indexURL: URL
    private let backupIndexURL: URL
    private let sessionsDirectoryURL: URL
    private let sessionDataProtector: any SessionDataProtecting
    private var sessionLookup: [UUID: TranscriptSession] = [:]

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil,
        sessionDataProtector: (any SessionDataProtecting)? = nil
    ) {
        self.fileManager = fileManager
        self.sessionDataProtector = sessionDataProtector ?? SessionDataProtectorFactory.automatic()

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupportDirectory = Self.makeAppSupportDirectory(fileManager: fileManager)
            self.storageURL = appSupportDirectory.appendingPathComponent("sessions.json")
        }
        self.backupStorageURL = Self.makeBackupURL(for: self.storageURL)
        self.indexURL = self.storageURL.deletingLastPathComponent().appendingPathComponent("sessions.index.json")
        self.backupIndexURL = self.storageURL.deletingLastPathComponent().appendingPathComponent("sessions.index.backup.json")
        self.sessionsDirectoryURL = self.storageURL.deletingLastPathComponent().appendingPathComponent("Sessions", isDirectory: true)

        load()
    }

    func add(_ session: TranscriptSession) throws {
        var updatedEntries = libraryEntries
        updatedEntries.removeAll { $0.id == session.id }
        updatedEntries.insert(SessionLibraryEntry(session: session), at: 0)
        updatedEntries = normalizedEntries(updatedEntries)
        let retainedIDs = Set(updatedEntries.map(\.id))

        do {
            try persistSessionFile(for: session)
            try persistIndex(updatedEntries)
            try cleanupUnreferencedSessionFiles(retainedIDs: retainedIDs)
            replaceState(
                with: updatedEntries,
                loadedSessions: upsertLoadedSession(session, retainedIDs: retainedIDs)
            )
            logger.debug(
                "session_saved",
                "Saved session history entry.",
                metadata: [
                    "session_id": session.id.uuidString,
                    "stored_sessions": "\(libraryEntries.count)"
                ]
            )
        } catch {
            logger.error(
                "session_save_failed",
                "Saving session history failed.",
                metadata: ["session_id": session.id.uuidString]
            )
            throw AppError.storageFailure(error.localizedDescription)
        }
    }

    @discardableResult
    func removeSessions(withIDs ids: Set<UUID>) throws -> [TranscriptSession] {
        guard !ids.isEmpty else {
            return []
        }

        let removedSessions = ids.compactMap { session(with: $0) }
        let remainingEntries = libraryEntries.filter { !ids.contains($0.id) }

        do {
            try persistIndex(remainingEntries)
            for id in ids {
                try? fileManager.removeItem(at: sessionFileURL(for: id))
            }
            try cleanupUnreferencedSessionFiles(retainedIDs: Set(remainingEntries.map(\.id)))
            replaceState(
                with: remainingEntries,
                loadedSessions: sessions.filter { !ids.contains($0.id) }
            )
            logger.info(
                "sessions_deleted",
                "Removed sessions from local history.",
                metadata: [
                    "removed_count": "\(removedSessions.count)",
                    "remaining_sessions": "\(remainingEntries.count)"
                ]
            )
            return removedSessions
        } catch {
            logger.error(
                "session_delete_failed",
                "Removing sessions from local history failed.",
                metadata: ["requested_count": "\(ids.count)"]
            )
            throw AppError.storageFailure(error.localizedDescription)
        }
    }

    func session(with id: UUID) -> TranscriptSession? {
        guard libraryEntries.contains(where: { $0.id == id }) else {
            return nil
        }

        if let session = sessionLookup[id] {
            return session
        }

        guard let session = loadSessionFile(with: id) else {
            return nil
        }

        cacheLoadedSession(session)
        return session
    }

    func allStoredSessionIDs() -> [UUID] {
        libraryEntries.map(\.id)
    }

    func allStoredSessions() -> [TranscriptSession] {
        libraryEntries.compactMap { session(with: $0.id) }
    }

    private func load() {
        if let state = loadPartitionedState(from: indexURL) {
            replaceState(with: state.entries, loadedSessions: state.loadedSessions)
            lastLoadRecoveryEvent = nil
            logger.info(
                "session_store_loaded",
                "Loaded partitioned session history from primary storage.",
                metadata: ["session_count": "\(libraryEntries.count)"]
            )
            return
        }

        if let backupState = loadPartitionedState(from: backupIndexURL) {
            replaceState(with: backupState.entries, loadedSessions: backupState.loadedSessions)
            try? persistIndex(backupState.entries)
            lastLoadRecoveryEvent = TranscriptStoreRecoveryEvent(
                source: .backup,
                recoveredSessionCount: backupState.entries.count
            )
            logger.warning(
                "session_store_recovered_from_backup",
                "Recovered partitioned session history from the backup index after the primary index failed to load.",
                metadata: ["session_count": "\(libraryEntries.count)"]
            )
            return
        }

        if let storedSessions = loadSessions(from: storageURL) {
            let normalizedStoredSessions = normalizedSessions(storedSessions)
            let entries = normalizedStoredSessions.map(SessionLibraryEntry.init(session:))
            try? persist(normalizedStoredSessions)
            replaceState(with: entries, loadedSessions: [])
            lastLoadRecoveryEvent = nil
            logger.info(
                "session_store_loaded",
                "Loaded legacy session history from primary storage and migrated it to partitioned storage.",
                metadata: ["session_count": "\(libraryEntries.count)"]
            )
            return
        }

        if let backupSessions = loadSessions(from: backupStorageURL) {
            let normalizedBackupSessions = normalizedSessions(backupSessions)
            let entries = normalizedBackupSessions.map(SessionLibraryEntry.init(session:))
            try? persist(normalizedBackupSessions)
            replaceState(with: entries, loadedSessions: [])
            lastLoadRecoveryEvent = TranscriptStoreRecoveryEvent(
                source: .backup,
                recoveredSessionCount: normalizedBackupSessions.count
            )
            logger.warning(
                "session_store_recovered_from_backup",
                "Recovered session history from the backup store after the primary store failed to load.",
                metadata: ["session_count": "\(libraryEntries.count)"]
            )
            return
        }

        replaceState(with: [], loadedSessions: [])
        if fileManager.fileExists(atPath: storageURL.path) ||
            fileManager.fileExists(atPath: indexURL.path) ||
            fileManager.fileExists(atPath: backupStorageURL.path) ||
            fileManager.fileExists(atPath: backupIndexURL.path) {
            lastLoadRecoveryEvent = TranscriptStoreRecoveryEvent(source: .failed, recoveredSessionCount: 0)
        } else {
            lastLoadRecoveryEvent = nil
        }
        logger.info("session_store_empty", "No existing session history was found on disk.")
    }

    private func persist(_ sessions: [TranscriptSession]) throws {
        let parentDirectoryURL = indexURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: sessionsDirectoryURL.path) {
            try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
        }

        let normalizedSessions = normalizedSessions(sessions)
        let normalizedIDs = Set(normalizedSessions.map(\.id))
        for session in normalizedSessions {
            let data = try sessionDataProtector.protect(encoder.encode(session))
            try data.write(to: sessionFileURL(for: session.id), options: [.atomic])
        }

        try persistIndex(normalizedSessions.map(SessionLibraryEntry.init(session:)))
        try cleanupUnreferencedSessionFiles(retainedIDs: normalizedIDs)
    }

    private func loadSessions(from url: URL) -> [TranscriptSession]? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([TranscriptSession].self, from: data)
        } catch {
            logger.warning(
                "session_store_decode_failed",
                "Session history could not be decoded from disk.",
                metadata: ["file": url.lastPathComponent]
            )
            return nil
        }
    }

    private func loadPartitionedState(from indexURL: URL) -> (entries: [SessionLibraryEntry], loadedSessions: [TranscriptSession])? {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return nil
        }

        do {
            let indexData = try Data(contentsOf: indexURL)
            let index = try decoder.decode(TranscriptStoreIndex.self, from: indexData)

            if !index.entries.isEmpty {
                return (normalizedEntries(index.entries), [])
            }

            let storedSessions = index.sessionIDs.compactMap { id in
                loadSessionFile(with: id)
            }
            guard storedSessions.count == index.sessionIDs.count else {
                return nil
            }

            let normalizedStoredSessions = normalizedSessions(storedSessions)
            let entries = normalizedStoredSessions.map(SessionLibraryEntry.init(session:))
            try? persistIndex(entries)
            return (entries, [])
        } catch {
            logger.warning(
                "session_store_partitioned_decode_failed",
                "Partitioned session history could not be decoded from disk.",
                metadata: ["file": indexURL.lastPathComponent]
            )
            return nil
        }
    }

    private func loadSessionFile(with id: UUID) -> TranscriptSession? {
        let fileURL = sessionFileURL(for: id)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let unprotectedData = try sessionDataProtector.unprotect(data)
            return try decoder.decode(TranscriptSession.self, from: unprotectedData)
        } catch {
            logger.warning(
                "session_body_decode_failed",
                "A stored session body could not be decoded from disk.",
                metadata: [
                    "session_id": id.uuidString,
                    "file": fileURL.lastPathComponent
                ]
            )
            return nil
        }
    }

    private func normalizedSessions(_ sessions: [TranscriptSession]) -> [TranscriptSession] {
        let uniqueSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) }).values
        return Array(uniqueSessions)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }

                return lhs.createdAt > rhs.createdAt
            }
            .prefix(StoragePolicy.maximumStoredSessions)
            .map { $0 }
    }

    private func normalizedEntries(_ entries: [SessionLibraryEntry]) -> [SessionLibraryEntry] {
        let uniqueEntries = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) }).values
        return Array(uniqueEntries)
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id.uuidString > rhs.id.uuidString
                }

                return lhs.createdAt > rhs.createdAt
            }
            .prefix(StoragePolicy.maximumStoredSessions)
            .map { $0 }
    }

    private func replaceState(with entries: [SessionLibraryEntry], loadedSessions: [TranscriptSession]) {
        libraryEntries = normalizedEntries(entries)
        let retainedIDs = Set(libraryEntries.map(\.id))
        sessions = normalizedSessions(loadedSessions).filter { retainedIDs.contains($0.id) }
        sessionLookup = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
    }

    private func persistIndex(_ entries: [SessionLibraryEntry]) throws {
        let parentDirectoryURL = indexURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }

        let normalizedEntries = normalizedEntries(entries)
        let index = TranscriptStoreIndex(entries: normalizedEntries)
        let indexData = try encoder.encode(index)
        try indexData.write(to: indexURL, options: [.atomic])
        try? indexData.write(to: backupIndexURL, options: [.atomic])
    }

    private func persistSessionFile(for session: TranscriptSession) throws {
        let parentDirectoryURL = indexURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: sessionsDirectoryURL.path) {
            try fileManager.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
        }

        let data = try sessionDataProtector.protect(encoder.encode(session))
        try data.write(to: sessionFileURL(for: session.id), options: [.atomic])
    }

    private func cleanupUnreferencedSessionFiles(retainedIDs: Set<UUID>) throws {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            let rawID = fileURL.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: rawID), !retainedIDs.contains(id) else {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func cacheLoadedSession(_ session: TranscriptSession) {
        guard libraryEntries.contains(where: { $0.id == session.id }) else {
            return
        }

        sessionLookup[session.id] = session
        sessions = upsertLoadedSession(session, retainedIDs: Set(libraryEntries.map(\.id)))
    }

    private func upsertLoadedSession(_ session: TranscriptSession, retainedIDs: Set<UUID>) -> [TranscriptSession] {
        var updatedSessions = sessions.filter { retainedIDs.contains($0.id) }
        updatedSessions.removeAll { $0.id == session.id }
        updatedSessions.insert(session, at: 0)
        return normalizedSessions(updatedSessions)
    }

    private static func makeAppSupportDirectory(fileManager: FileManager) -> URL {
        AppSupportLocation.appDirectory(fileManager: fileManager)
    }

    private static func makeBackupURL(for storageURL: URL) -> URL {
        storageURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private func sessionFileURL(for id: UUID) -> URL {
        sessionsDirectoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }
}

private struct TranscriptStoreIndex: Codable {
    let version: Int
    let entries: [SessionLibraryEntry]
    let sessionIDs: [UUID]

    init(version: Int = 2, entries: [SessionLibraryEntry], sessionIDs: [UUID]? = nil) {
        self.version = version
        self.entries = entries
        self.sessionIDs = sessionIDs ?? entries.map(\.id)
    }
}

struct TranscriptStoreRecoveryEvent: Equatable {
    enum Source: Equatable {
        case backup
        case failed
    }

    let source: Source
    let recoveredSessionCount: Int

    var userMessage: String {
        switch source {
        case .backup:
            return "Session history was recovered from the local backup. \(recoveredSessionCount) session\(recoveredSessionCount == 1 ? "" : "s") restored."
        case .failed:
            return "Session history could not be read from the primary or backup store. A new empty library was opened."
        }
    }
}
