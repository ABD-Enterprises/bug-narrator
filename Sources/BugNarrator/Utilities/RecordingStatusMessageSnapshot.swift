import Foundation

struct RecordingStatusMessageSnapshot: Equatable {
    var audioSource: RecordingAudioSource
    var hasUsableAIProviderCredential: Bool
    var aiProviderCompatibilityIssue: String?
    var autoExtractIssues: Bool
    var autoCopyTranscript: Bool
}
