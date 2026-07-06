import Combine
import Foundation

struct RecordingStatusMessageSnapshot: Equatable {
    var audioSource: RecordingAudioSource
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
        transcriptionProgressMessage(step: 1, action: "Uploading audio to OpenAI for transcription...")
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
}
