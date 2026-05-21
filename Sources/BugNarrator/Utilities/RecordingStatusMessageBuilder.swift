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
