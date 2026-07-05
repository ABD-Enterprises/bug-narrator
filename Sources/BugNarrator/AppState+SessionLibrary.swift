import Foundation

extension AppState {
    // MARK: - Methods

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

    // MARK: - Computed properties

    var currentTranscript: TranscriptSession? {
        get { sessionLibrary.currentTranscript }
        set { sessionLibrary.currentTranscript = newValue }
    }

    var selectedTranscriptID: UUID? {
        get { sessionLibrary.selectedTranscriptID }
        set { sessionLibrary.selectedTranscriptID = newValue }
    }
}
