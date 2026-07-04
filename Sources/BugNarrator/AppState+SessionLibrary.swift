import Foundation

extension AppState {
    func copyDisplayedTranscript() {
        sessionLibraryStatusPresenter.presentDisplayedTranscriptCopyResult(sessionLibrary.copyDisplayedTranscript())
    }

    func saveCurrentTranscriptToHistory() {
        do {
            sessionLibraryStatusPresenter.presentSavedSession(try sessionLibrary.saveCurrentTranscriptToHistory())
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }

    func deleteDisplayedTranscript() {
        do {
            sessionLibraryStatusPresenter.presentDeletedCount(try sessionLibrary.deleteDisplayedTranscript())
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        do {
            sessionLibraryStatusPresenter.presentDeletedCount(try sessionLibrary.deleteSessions(withIDs: ids))
        } catch {
            sessionLibraryStatusPresenter.presentFailure(error)
        }
    }
}
