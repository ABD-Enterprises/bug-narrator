import Foundation

final class TranscriptStore: ObservableObject {
    @Published private(set) var sessions: [TranscriptSession] = []
    @Published private(set) var libraryEntries: [SessionLibraryEntry] = []
    private let logger = DiagnosticsLogger(category: .sessionLibrary)

    private enum StoragePolicy {
        static let maximumStoredSessions = 500
    }

    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storageURL: URL
    private let backupStorageURL: URL
    private var sessionLookup: [UUID: TranscriptSession] = [:]

    init(fileManager: FileManager = .default, storageURL: URL? = nil) {
        self.fileManager = fileManager

        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupportDirectory = Self.makeAppSupportDirectory(fileManager: fileManager)
            self.storageURL = appSupportDirectory.appendingPathComponent("sessions.json")
        }
        self.backupStorageURL = Self.makeBackupURL(for: self.storageURL)

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
        if let storedSessions = loadSessions(from: storageURL) {
            replaceState(with: normalizedSessions(storedSessions))
            logger.info(
                "session_store_loaded",
                "Loaded session history from primary storage.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        if let backupSessions = loadSessions(from: backupStorageURL) {
            let normalizedBackupSessions = normalizedSessions(backupSessions)
            replaceState(with: normalizedBackupSessions)
            try? persist(normalizedBackupSessions)
            logger.warning(
                "session_store_recovered_from_backup",
                "Recovered session history from the backup store after the primary store failed to load.",
                metadata: ["session_count": "\(sessions.count)"]
            )
            return
        }

        replaceState(with: [])
        logger.info("session_store_empty", "No existing session history was found on disk.")
    }

    private func persist(_ sessions: [TranscriptSession]) throws {
        let parentDirectoryURL = storageURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDirectoryURL.path) {
            try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        }

        let data = try encoder.encode(sessions)
        try data.write(to: storageURL, options: [.atomic])
        try? data.write(to: backupStorageURL, options: [.atomic])
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
}
