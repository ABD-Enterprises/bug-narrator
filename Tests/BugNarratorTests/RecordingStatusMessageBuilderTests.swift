import XCTest
@testable import BugNarrator

final class RecordingStatusMessageBuilderTests: XCTestCase {
    func testRecordingDetailMessageForAudioSources() {
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingDetailMessage(
                audioSource: .microphone,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil
            ),
            "Recording in progress."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingDetailMessage(
                audioSource: .systemAudio,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil
            ),
            "Recording system audio."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingDetailMessage(
                audioSource: .microphoneAndSystemAudio,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: nil
            ),
            "Recording microphone and system audio."
        )
    }

    func testRecordingDetailMessageIncludesSetupAndCompatibilityGuidance() {
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingDetailMessage(
                audioSource: .microphone,
                hasUsableAIProviderCredential: false,
                aiProviderCompatibilityIssue: nil
            ),
            "Recording in progress. Finish the AI provider setup in Settings before stopping to transcribe this session."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingDetailMessage(
                audioSource: .systemAudio,
                hasUsableAIProviderCredential: true,
                aiProviderCompatibilityIssue: "Choose a non-default API base URL for the OpenAI-Compatible provider."
            ),
            "Recording system audio. Choose a non-default API base URL for the OpenAI-Compatible provider."
        )
    }

    func testRecordingActivityReasonForAudioSources() {
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingActivityReason(audioSource: .microphone),
            "Recording a spoken feedback session"
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingActivityReason(audioSource: .systemAudio),
            "Recording system audio for a feedback session"
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.recordingActivityReason(audioSource: .microphoneAndSystemAudio),
            "Recording microphone and system audio for a feedback session"
        )
    }

    func testTranscriptionProgressMessageUsesAutoExtractionStepCount() {
        XCTAssertEqual(
            RecordingStatusMessageBuilder.transcriptionProgressMessage(
                step: 1,
                action: "Uploading audio to OpenAI for transcription...",
                autoExtractIssues: false
            ),
            "Step 1 of 2: Uploading audio to OpenAI for transcription..."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.transcriptionProgressMessage(
                step: 3,
                action: "Extracting reviewable issues...",
                autoExtractIssues: true
            ),
            "Step 3 of 3: Extracting reviewable issues..."
        )
    }

    func testTranscriptionSuccessMessageVariants() {
        XCTAssertEqual(
            RecordingStatusMessageBuilder.transcriptionSuccessMessage(
                autoExtractIssues: true,
                autoCopyTranscript: false
            ),
            "Session saved. Transcript and extracted issues are ready."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.transcriptionSuccessMessage(
                autoExtractIssues: false,
                autoCopyTranscript: true
            ),
            "Session saved. Transcript copied to the clipboard."
        )
        XCTAssertEqual(
            RecordingStatusMessageBuilder.transcriptionSuccessMessage(
                autoExtractIssues: false,
                autoCopyTranscript: false
            ),
            "Session saved locally and ready for review."
        )
    }

    func testProviderUsesCurrentSnapshotValuesAtCallTime() {
        var snapshot = RecordingStatusMessageSnapshot(
            audioSource: .microphone,
            hasUsableAIProviderCredential: false,
            aiProviderCompatibilityIssue: nil,
            autoExtractIssues: false,
            autoCopyTranscript: true
        )
        let provider = RecordingStatusMessageProvider {
            snapshot
        }

        XCTAssertEqual(
            provider.recordingDetailMessage(),
            "Recording in progress. Finish the AI provider setup in Settings before stopping to transcribe this session."
        )
        XCTAssertEqual(
            provider.transcriptionProgressMessage(step: 1, action: "Uploading audio to OpenAI for transcription..."),
            "Step 1 of 2: Uploading audio to OpenAI for transcription..."
        )
        XCTAssertEqual(provider.transcriptionSuccessMessage(), "Session saved. Transcript copied to the clipboard.")

        snapshot = RecordingStatusMessageSnapshot(
            audioSource: .microphoneAndSystemAudio,
            hasUsableAIProviderCredential: true,
            aiProviderCompatibilityIssue: "Choose a non-default API base URL for the OpenAI-Compatible provider.",
            autoExtractIssues: true,
            autoCopyTranscript: false
        )

        XCTAssertEqual(
            provider.recordingDetailMessage(),
            "Recording microphone and system audio. Choose a non-default API base URL for the OpenAI-Compatible provider."
        )
        XCTAssertEqual(
            provider.recordingActivityReason(),
            "Recording microphone and system audio for a feedback session"
        )
        XCTAssertEqual(
            provider.transcriptionProgressMessage(step: 3, action: "Extracting reviewable issues..."),
            "Step 3 of 3: Extracting reviewable issues..."
        )
        XCTAssertEqual(provider.transcriptionSuccessMessage(), "Session saved. Transcript and extracted issues are ready.")
    }
}
