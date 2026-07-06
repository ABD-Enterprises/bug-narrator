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

