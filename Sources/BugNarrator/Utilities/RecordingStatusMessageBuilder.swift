import Foundation

enum RecordingStatusMessageBuilder {
    static func recordingDetailMessage(
        audioSource: RecordingAudioSource,
        hasUsableAIProviderCredential: Bool,
        aiProviderCompatibilityIssue: String?
    ) -> String {
        let prefix: String
        switch audioSource {
        case .microphone:
            prefix = "Recording in progress."
        case .systemAudio:
            prefix = "Recording system audio."
        case .microphoneAndSystemAudio:
            prefix = "Recording microphone and system audio."
        }

        if hasUsableAIProviderCredential && aiProviderCompatibilityIssue == nil {
            return prefix
        }

        if let aiProviderCompatibilityIssue {
            return "\(prefix) \(aiProviderCompatibilityIssue)"
        }

        return "\(prefix) Finish the AI provider setup in Settings before stopping to transcribe this session."
    }

    static func recordingActivityReason(audioSource: RecordingAudioSource) -> String {
        switch audioSource {
        case .microphone:
            return "Recording a spoken feedback session"
        case .systemAudio:
            return "Recording system audio for a feedback session"
        case .microphoneAndSystemAudio:
            return "Recording microphone and system audio for a feedback session"
        }
    }

    static func transcriptionProgressMessage(
        step: Int,
        action: String,
        autoExtractIssues: Bool
    ) -> String {
        let totalSteps = autoExtractIssues ? 3 : 2
        return "Step \(step) of \(totalSteps): \(action)"
    }

    static func transcriptionSuccessMessage(
        autoExtractIssues: Bool,
        autoCopyTranscript: Bool
    ) -> String {
        if autoExtractIssues {
            return "Session saved. Transcript and extracted issues are ready."
        }

        if autoCopyTranscript {
            return "Session saved. Transcript copied to the clipboard."
        }

        return "Session saved locally and ready for review."
    }
}

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
