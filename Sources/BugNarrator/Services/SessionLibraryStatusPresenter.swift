import Combine
import Foundation

@MainActor
final class SessionLibraryStatusPresenter {
    private let errorPresenter: AppErrorPresenter
    var prepareErrorPresentationSideEffects: () -> Void

    init(
        errorPresenter: AppErrorPresenter,
        prepareErrorPresentationSideEffects: @escaping () -> Void = {}
    ) {
        self.errorPresenter = errorPresenter
        self.prepareErrorPresentationSideEffects = prepareErrorPresentationSideEffects
    }

    func presentDisplayedTranscriptCopyResult(_ result: DisplayedTranscriptCopyResult) {
        if let status = DisplayedTranscriptCopyStatusPresenter.status(for: result) {
            errorPresenter.setStatus(status)
        }
    }

    func presentSavedSession(_ savedSession: TranscriptSession?) {
        if let status = TranscriptSaveStatusPresenter.status(savedSession: savedSession) {
            errorPresenter.setStatus(status)
        }
    }

    func presentDeletedCount(_ deletedCount: Int) {
        if let status = SessionDeletionStatusPresenter.status(deletedCount: deletedCount) {
            errorPresenter.setStatus(status)
        }
    }

    func presentFailure(_ error: Error) {
        prepareErrorPresentationSideEffects()
        _ = errorPresenter.presentError(error, operation: .sessionLibrary, fallback: { .storageFailure($0) })
    }
}
