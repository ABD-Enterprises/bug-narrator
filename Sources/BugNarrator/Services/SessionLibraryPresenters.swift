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

