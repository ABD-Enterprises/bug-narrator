import Combine
import Foundation

@MainActor
final class PostTranscriptionStatusPresenter {
    private let recordingStatusMessages: RecordingStatusMessageProvider
    private let setStatus: (AppStatus) -> Void
    private let showTranscriptWindow: () -> Void

    init(
        recordingStatusMessages: RecordingStatusMessageProvider,
        setStatus: @escaping (AppStatus) -> Void,
        showTranscriptWindow: @escaping () -> Void
    ) {
        self.recordingStatusMessages = recordingStatusMessages
        self.setStatus = setStatus
        self.showTranscriptWindow = showTranscriptWindow
    }

    func presentUploadProgress() {
        setStatus(.transcribing(recordingStatusMessages.transcriptionUploadProgressMessage()))
    }

    func presentSavingProgress(mode: PostTranscriptionPipelineMode) {
        setStatus(.transcribing(recordingStatusMessages.transcriptionSavingProgressMessage(mode: mode)))
    }

    func presentIssueExtractionProgress() {
        setStatus(.transcribing(recordingStatusMessages.transcriptionIssueExtractionProgressMessage()))
    }

    func presentTranscriptWindow() {
        showTranscriptWindow()
    }

    func presentSuccess() {
        setStatus(.success(recordingStatusMessages.transcriptionSuccessMessage()))
    }
}
