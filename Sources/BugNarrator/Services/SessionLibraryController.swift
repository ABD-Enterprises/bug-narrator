import Combine
import Foundation

enum DisplayedTranscriptCopyResult: Equatable {
    case noDisplayedTranscript
    case transcriptUnavailable
    case copied
}

enum DisplayedTranscriptCopyStatusPresenter {
    static func status(for result: DisplayedTranscriptCopyResult) -> AppStatus? {
        switch result {
        case .noDisplayedTranscript:
            return nil
        case .transcriptUnavailable:
            return .error("Transcription is not available yet. Retry the preserved session first.")
        case .copied:
            return .success("Transcript copied to the clipboard.")
        }
    }
}

enum TranscriptSaveStatusPresenter {
    static func status(savedSession: TranscriptSession?) -> AppStatus? {
        guard savedSession != nil else {
            return nil
        }

        return .success("Transcript saved to session history.")
    }
}

enum SessionDeletionStatusPresenter {
    static func status(deletedCount: Int) -> AppStatus? {
        guard deletedCount > 0 else {
            return nil
        }

        return .success(deletedCount == 1 ? "Deleted 1 session." : "Deleted \(deletedCount) sessions.")
    }
}

@MainActor
final class SessionLibraryController: ObservableObject {
    @Published var currentTranscript: TranscriptSession?
    @Published var selectedTranscriptID: UUID?

    private let transcriptStore: TranscriptStore
    private let artifactsService: any SessionArtifactsManaging
    private let clipboardService: any ClipboardWriting
    private let logger: DiagnosticsLogger

    init(
        transcriptStore: TranscriptStore,
        artifactsService: any SessionArtifactsManaging,
        clipboardService: any ClipboardWriting,
        logger: DiagnosticsLogger = DiagnosticsLogger(category: .sessionLibrary)
    ) {
        self.transcriptStore = transcriptStore
        self.artifactsService = artifactsService
        self.clipboardService = clipboardService
        self.logger = logger
        self.selectedTranscriptID = transcriptStore.libraryEntries.first?.id
    }

    var displayedTranscript: TranscriptSession? {
        if let selectedTranscriptID {
            if currentTranscript?.id == selectedTranscriptID {
                return currentTranscript
            }

            if let storedSession = transcriptStore.session(with: selectedTranscriptID) {
                return storedSession
            }
        }

        if let currentTranscript {
            return currentTranscript
        }

        return transcriptStore.libraryEntries.first.flatMap { transcriptStore.session(with: $0.id) }
    }

    var currentTranscriptIsPersisted: Bool {
        guard let currentTranscript else {
            return false
        }

        return transcriptStore.session(with: currentTranscript.id) == currentTranscript
    }

    func sessionSnapshot(with sessionID: UUID) -> TranscriptSession? {
        if currentTranscript?.id == sessionID {
            return currentTranscript
        }

        return transcriptStore.session(with: sessionID)
    }

    func editableSession(with sessionID: UUID) -> TranscriptSession? {
        sessionSnapshot(with: sessionID)
    }

    func refreshSelectionAfterLibraryReload() {
        if let selectedTranscriptID, sessionSnapshot(with: selectedTranscriptID) != nil {
            return
        }

        selectedTranscriptID = preferredTranscriptSelection()
    }

    func setCurrentTranscript(_ session: TranscriptSession?) {
        currentTranscript = session
    }

    func stageCurrentTranscript(
        _ session: TranscriptSession,
        autoCopyTranscript: Bool = false
    ) {
        currentTranscript = session
        selectedTranscriptID = session.id

        if autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }
    }

    func selectLatestPendingTranscriptionSession() {
        selectedTranscriptID = transcriptStore.latestPendingTranscriptionSession?.id
    }

    @discardableResult
    func saveCurrentTranscriptToHistory() throws -> TranscriptSession? {
        guard let currentTranscript, !currentTranscriptIsPersisted else {
            selectedTranscriptID = currentTranscript?.id
            return nil
        }

        try transcriptStore.add(currentTranscript)
        selectedTranscriptID = currentTranscript.id
        logger.info(
            "unsaved_transcript_persisted",
            "Saved the in-memory transcript into local session history.",
            metadata: ["session_id": currentTranscript.id.uuidString]
        )
        return currentTranscript
    }

    @discardableResult
    func deleteDisplayedTranscript() throws -> Int {
        guard let displayedTranscript else {
            return 0
        }

        return try deleteSessions(withIDs: [displayedTranscript.id])
    }

    @discardableResult
    func deleteSessions(withIDs ids: Set<UUID>) throws -> Int {
        guard !ids.isEmpty else {
            return 0
        }

        let wasSelectedTranscriptDeleted = selectedTranscriptID.map(ids.contains) ?? false
        let deletingUnsavedCurrentTranscript = currentTranscript
            .map { ids.contains($0.id) && transcriptStore.session(with: $0.id) == nil }
            ?? false

        let removedSessions = try transcriptStore.removeSessions(withIDs: ids)
        var sessionsToCleanup = removedSessions
        if let currentTranscript,
           ids.contains(currentTranscript.id),
           !removedSessions.contains(where: { $0.id == currentTranscript.id }),
           transcriptStore.session(with: currentTranscript.id) == nil {
            sessionsToCleanup.append(currentTranscript)
        }
        sessionsToCleanup.forEach(cleanupArtifactsForDeletedSession)

        if currentTranscript.map({ ids.contains($0.id) }) == true {
            currentTranscript = nil
        }

        if wasSelectedTranscriptDeleted || selectedTranscriptID == nil {
            selectedTranscriptID = preferredTranscriptSelection()
        }

        let deletedCount = removedSessions.count + (deletingUnsavedCurrentTranscript ? 1 : 0)
        if deletedCount > 0 {
            logger.info(
                "sessions_deleted_from_library",
                "Deleted sessions from the library.",
                metadata: ["deleted_count": "\(deletedCount)"]
            )
        }
        return deletedCount
    }

    func persistCompletedTranscript(
        _ session: TranscriptSession,
        autoCopyTranscript: Bool
    ) throws {
        try transcriptStore.add(session)
        selectedTranscriptID = session.id

        if autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }

        logger.info(
            "transcript_persisted",
            "Persisted a completed transcript session.",
            metadata: [
                "session_id": session.id.uuidString,
                "auto_saved": "required",
                "auto_copied": autoCopyTranscript ? "yes" : "no"
            ]
        )
    }

    func copyDisplayedTranscript() -> DisplayedTranscriptCopyResult {
        guard let transcript = displayedTranscript else {
            return .noDisplayedTranscript
        }

        guard transcript.hasTranscriptContent else {
            return .transcriptUnavailable
        }

        clipboardService.copy(transcript.transcript)
        return .copied
    }

    func persistRetryableSession(_ session: TranscriptSession) throws {
        try transcriptStore.add(session)
        stageCurrentTranscript(session)
    }

    func persistUpdatedSession(
        _ session: TranscriptSession,
        updatedAt: Date = Date(),
        autoCopyTranscript: Bool = false
    ) throws {
        var session = session
        session.updatedAt = updatedAt

        currentTranscript = session

        if transcriptStore.session(with: session.id) != nil {
            try transcriptStore.add(session)
        }

        if autoCopyTranscript {
            clipboardService.copy(session.transcript)
        }

        selectedTranscriptID = session.id
        logger.debug(
            "session_updated",
            "Updated a transcript session in memory or local storage.",
            metadata: ["session_id": session.id.uuidString]
        )
    }

    private func preferredTranscriptSelection() -> UUID? {
        if let currentTranscript, !currentTranscriptIsPersisted {
            return currentTranscript.id
        }

        return transcriptStore.libraryEntries.first?.id
    }

    private func cleanupArtifactsForDeletedSession(_ session: TranscriptSession) {
        if let artifactsDirectoryURL = session.artifactsDirectoryURL {
            artifactsService.removeArtifactsDirectory(at: artifactsDirectoryURL)
            return
        }

        let directories = Set(
            session.screenshots.map { screenshot in
                screenshot.fileURL.deletingLastPathComponent()
            }
        )

        directories.forEach { directoryURL in
            artifactsService.removeArtifactsDirectory(at: directoryURL)
        }
    }
}
