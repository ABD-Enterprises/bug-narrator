import Foundation

struct LocalDataDeletionOutcome: Equatable {
    let deletedSessionCount: Int

    var statusMessage: String {
        if deletedSessionCount == 0 {
            return "Cleared local diagnostics and export history."
        }

        if deletedSessionCount == 1 {
            return "Deleted 1 local session and cleared local diagnostics."
        }

        return "Deleted \(deletedSessionCount) local sessions and cleared local diagnostics."
    }
}

enum LocalDataDeletionResult: Equatable {
    case blocked(message: String)
    case deleted(LocalDataDeletionOutcome)
}

@MainActor
final class LocalDataDeletionController {
    private let transcriptStore: TranscriptStore
    private let sessionLibrary: SessionLibraryController
    private let supportDataController: SupportDataController
    private let exportHistoryController: ExportHistoryController

    init(
        transcriptStore: TranscriptStore,
        sessionLibrary: SessionLibraryController,
        supportDataController: SupportDataController,
        exportHistoryController: ExportHistoryController
    ) {
        self.transcriptStore = transcriptStore
        self.sessionLibrary = sessionLibrary
        self.supportDataController = supportDataController
        self.exportHistoryController = exportHistoryController
    }

    func deleteAllLocalData(
        currentTranscript: TranscriptSession?,
        statusPhase: AppStatus.Phase
    ) async throws -> LocalDataDeletionResult {
        guard statusPhase != .recording, statusPhase != .transcribing else {
            return .blocked(message: "Stop recording or transcription before deleting local data.")
        }

        return .deleted(try await deleteAllLocalData(currentTranscript: currentTranscript))
    }

    func deleteAllLocalData(currentTranscript: TranscriptSession?) async throws -> LocalDataDeletionOutcome {
        let idsToDelete = Set(transcriptStore.allStoredSessionIDs())
            .union(currentTranscript.map { [$0.id] } ?? [])
        let deletedSessionCount: Int

        if idsToDelete.isEmpty {
            deletedSessionCount = 0
        } else {
            deletedSessionCount = try sessionLibrary.deleteSessions(withIDs: idsToDelete)
        }

        await supportDataController.clearLocalPrivacyArtifacts()
        await exportHistoryController.refreshExportHistory()

        return LocalDataDeletionOutcome(deletedSessionCount: deletedSessionCount)
    }
}
