import Foundation

extension AppState {
    func copyDisplayedTranscript() {
        sessionLibraryStatusPresenter.presentDisplayedTranscriptCopyResult(sessionLibrary.copyDisplayedTranscript())
    }

    func saveCurrentTranscriptToHistory() {
        sessionLibraryStatusPresenter.present(
            { try sessionLibrary.saveCurrentTranscriptToHistory() },
            success: { sessionLibraryStatusPresenter.presentSavedSession($0) }
        )
    }

    func deleteDisplayedTranscript() {
        sessionLibraryStatusPresenter.present(
            { try sessionLibrary.deleteDisplayedTranscript() },
            success: { sessionLibraryStatusPresenter.presentDeletedCount($0) }
        )
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        sessionLibraryStatusPresenter.present(
            { try sessionLibrary.deleteSessions(withIDs: ids) },
            success: { sessionLibraryStatusPresenter.presentDeletedCount($0) }
        )
    }
}
