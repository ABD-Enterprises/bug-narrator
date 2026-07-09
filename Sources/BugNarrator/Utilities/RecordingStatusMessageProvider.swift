import Combine
import Foundation

struct RecordingStatusMessageSnapshot: Equatable {
    var audioSource: RecordingAudioSource
    var aiProvider: AIProvider = .openAI
    var hasUsableAIProviderCredential: Bool
    var aiProviderCompatibilityIssue: String?
    var autoExtractIssues: Bool
    var autoCopyTranscript: Bool
}

final class RecordingStatusMessageProvider {
    private let snapshot: () -> RecordingStatusMessageSnapshot

    init(snapshot: @escaping () -> RecordingStatusMessageSnapshot) {
        self.snapshot = snapshot
    }

    func recordingDetailMessage() -> String {
        let snapshot = snapshot()
        return RecordingStatusMessageBuilder.recordingDetailMessage(
            audioSource: snapshot.audioSource,
            hasUsableAIProviderCredential: snapshot.hasUsableAIProviderCredential,
            aiProviderCompatibilityIssue: snapshot.aiProviderCompatibilityIssue
        )
    }

    func recordingActivityReason() -> String {
        RecordingStatusMessageBuilder.recordingActivityReason(audioSource: snapshot().audioSource)
    }

    func transcriptionProgressMessage(step: Int, action: String) -> String {
        RecordingStatusMessageBuilder.transcriptionProgressMessage(
            step: step,
            action: action,
            autoExtractIssues: snapshot().autoExtractIssues
        )
    }

    func transcriptionUploadProgressMessage() -> String {
        let snapshot = snapshot()
        return RecordingStatusMessageBuilder.transcriptionProgressMessage(
            step: 1,
            action: transcriptionUploadAction(for: snapshot.aiProvider),
            autoExtractIssues: snapshot.autoExtractIssues
        )
    }

    func transcriptionRetryProgressMessage() -> String {
        transcriptionProgressMessage(step: 1, action: "Retrying transcription from the preserved recording...")
    }

    func transcriptionSavingProgressMessage(mode: PostTranscriptionPipelineMode) -> String {
        transcriptionProgressMessage(step: 2, action: mode.savingAction)
    }

    func transcriptionIssueExtractionProgressMessage() -> String {
        transcriptionProgressMessage(step: 3, action: "Extracting reviewable issues...")
    }

    func transcriptionSuccessMessage() -> String {
        let snapshot = snapshot()
        return RecordingStatusMessageBuilder.transcriptionSuccessMessage(
            autoExtractIssues: snapshot.autoExtractIssues,
            autoCopyTranscript: snapshot.autoCopyTranscript
        )
    }

    private func transcriptionUploadAction(for provider: AIProvider) -> String {
        switch provider {
        case .openAI:
            return "Uploading audio to OpenAI for transcription..."
        case .openAICompatible:
            return "Uploading audio to the OpenAI-compatible provider for transcription..."
        case .localCompatible:
            return "Sending audio to the local-compatible transcription endpoint..."
        case .parakeetLocal:
            return "Sending audio to the local Parakeet server for transcription..."
        }
    }
}

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
