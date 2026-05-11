import Foundation

final class TranscriptStore: ObservableObject {
    @Published private(set) var sessions: [TranscriptSession] = []
    @Published private(set) var libraryEntries: [SessionLibraryEntry] = []
    @Published private(set) var lastLoadRecoveryEvent: TranscriptStoreRecoveryEvent?
    private let logger = DiagnosticsLogger(category: .sessionLibrary)

    var pendingTranscriptionSessions: [TranscriptSession] {
        sessions.filter(\.requiresTranscriptionRetry)
    }

    var pendingTranscriptionSessionCount: Int {
        pendingTranscriptionSessions.count
    }

    var latestPendingTranscriptionSession: TranscriptSession? {
        pendingTranscriptionSessions.first
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
        var updatedSessions = sessions
        updatedSessions.removeAll { $0.id == session.id }
        updatedSessions.insert(session, at: 0)
        updatedSessions = normalizedSessions(updatedSessions)

        do {
            try persist(updatedSessions)
            replaceState(with: updatedSessions)
            logger.debug(
                "session_saved",
                "Saved session history entry.",
                metadata: [
                    "session_id": session.id.uuidString,
                    "stored_sessions": "\(sessions.count)"
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

        let removedSessions = sessions.filter { ids.contains($0.id) }
        let remainingSessions = sessions.filter { !ids.contains($0.id) }

        do {
            try persist(remainingSessions)
            replaceState(with: remainingSessions)
            logger.info(
                "sessions_deleted",
                "Removed sessions from local history.",
                metadata: [
                    "removed_count": "\(removedSessions.count)",
                    "remaining_sessions": "\(remainingSessions.count)"
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
        sessionLookup[id]
    }

    private func load() {
        if let storedSessions = loadPartitionedSessions(from: indexURL) {
            replaceState(with: normalizedSessions(storedSessions))
            lastLoadRecoveryEvent = nil
            logger.info(
                "session_store_loaded",
                "Loaded partitioned session history from primary storage.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        if let backupSessions = loadPartitionedSessions(from: backupIndexURL) {
            let normalizedBackupSessions = normalizedSessions(backupSessions)
            replaceState(with: normalizedBackupSessions)
            try? persist(normalizedBackupSessions)
            lastLoadRecoveryEvent = TranscriptStoreRecoveryEvent(
                source: .backup,
                recoveredSessionCount: normalizedBackupSessions.count
            )
            logger.warning(
                "session_store_recovered_from_backup",
                "Recovered partitioned session history from the backup index after the primary index failed to load.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        if let storedSessions = loadSessions(from: storageURL) {
            let normalizedStoredSessions = normalizedSessions(storedSessions)
            replaceState(with: normalizedStoredSessions)
            try? persist(normalizedStoredSessions)
            lastLoadRecoveryEvent = nil
            logger.info(
                "session_store_loaded",
                "Loaded legacy session history from primary storage and migrated it to partitioned storage.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        if let backupSessions = loadSessions(from: backupStorageURL) {
            let normalizedBackupSessions = normalizedSessions(backupSessions)
            replaceState(with: normalizedBackupSessions)
            try? persist(normalizedBackupSessions)
            lastLoadRecoveryEvent = TranscriptStoreRecoveryEvent(
                source: .backup,
                recoveredSessionCount: normalizedBackupSessions.count
            )
            logger.warning(
                "session_store_recovered_from_backup",
                "Recovered session history from the backup store after the primary store failed to load.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        replaceState(with: [])
        if fileManager.fileExists(atPath: storageURL.path) {
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

        let normalizedIDs = Set(sessions.map(\.id))
        for session in sessions {
            let data = try sessionDataProtector.protect(encoder.encode(session))
            try data.write(to: sessionFileURL(for: session.id), options: [.atomic])
        }

        let index = TranscriptStoreIndex(sessionIDs: sessions.map(\.id))
        let indexData = try encoder.encode(index)
        try indexData.write(to: indexURL, options: [.atomic])
        try? indexData.write(to: backupIndexURL, options: [.atomic])

        if let fileURLs = try? fileManager.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        ) {
            for fileURL in fileURLs where fileURL.pathExtension == "json" {
                let rawID = fileURL.deletingPathExtension().lastPathComponent
                guard let id = UUID(uuidString: rawID), !normalizedIDs.contains(id) else {
                    continue
                }
                try? fileManager.removeItem(at: fileURL)
            }
        }
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

    private func loadPartitionedSessions(from indexURL: URL) -> [TranscriptSession]? {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return nil
        }

        do {
            let indexData = try Data(contentsOf: indexURL)
            let index = try decoder.decode(TranscriptStoreIndex.self, from: indexData)
            let sessions = try index.sessionIDs.map { id in
                let data = try Data(contentsOf: sessionFileURL(for: id))
                let unprotectedData = try sessionDataProtector.unprotect(data)
                return try decoder.decode(TranscriptSession.self, from: unprotectedData)
            }
            return sessions
        } catch {
            logger.warning(
                "session_store_partitioned_decode_failed",
                "Partitioned session history could not be decoded from disk.",
                metadata: ["file": indexURL.lastPathComponent]
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

    private func replaceState(with sessions: [TranscriptSession]) {
        self.sessions = sessions
        sessionLookup = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        libraryEntries = sessions.map(SessionLibraryEntry.init(session:))
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
    let sessionIDs: [UUID]

    init(version: Int = 1, sessionIDs: [UUID]) {
        self.version = version
        self.sessionIDs = sessionIDs
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
