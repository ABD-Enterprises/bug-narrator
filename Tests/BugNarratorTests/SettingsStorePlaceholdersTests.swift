import XCTest
@testable import BugNarrator

@MainActor
final class SettingsStorePlaceholdersTests: XCTestCase {
    // MARK: - supportsIssueExtraction

    func test_supportsIssueExtraction_openAI_returnsTrue() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAI

        XCTAssertTrue(harness.settingsStore.supportsIssueExtraction)
    }

    func test_supportsIssueExtraction_openAICompatible_returnsTrue() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAICompatible

        XCTAssertTrue(harness.settingsStore.supportsIssueExtraction)
    }

    func test_supportsIssueExtraction_localCompatible_returnsTrue() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .localCompatible

        XCTAssertTrue(harness.settingsStore.supportsIssueExtraction)
    }

    func test_supportsIssueExtraction_parakeetLocal_returnsFalse() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .parakeetLocal

        XCTAssertFalse(harness.settingsStore.supportsIssueExtraction)
    }

    // MARK: - transcriptionModelPlaceholder

    func test_transcriptionModelPlaceholder_openAI_returnsWhisper1() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.transcriptionModelPlaceholder, "whisper-1")
    }

    func test_transcriptionModelPlaceholder_openAICompatible_returnsProviderModelHint() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAICompatible

        XCTAssertEqual(harness.settingsStore.transcriptionModelPlaceholder, "Provider transcription model")
    }

    func test_transcriptionModelPlaceholder_localCompatible_returnsLocalModelHint() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .localCompatible

        XCTAssertEqual(harness.settingsStore.transcriptionModelPlaceholder, "Local transcription model")
    }

    func test_transcriptionModelPlaceholder_parakeetLocal_returnsParakeetModelID() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .parakeetLocal

        XCTAssertEqual(harness.settingsStore.transcriptionModelPlaceholder, "parakeet-tdt-0.6b-v3")
    }

    // MARK: - issueExtractionModelPlaceholder

    func test_issueExtractionModelPlaceholder_openAI_returnsGpt41Mini() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAI

        XCTAssertEqual(harness.settingsStore.issueExtractionModelPlaceholder, "gpt-4.1-mini")
    }

    func test_issueExtractionModelPlaceholder_openAICompatible_returnsProviderChatHint() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAICompatible

        XCTAssertEqual(harness.settingsStore.issueExtractionModelPlaceholder, "Provider chat model")
    }

    func test_issueExtractionModelPlaceholder_localCompatible_returnsLocalChatHint() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .localCompatible

        XCTAssertEqual(harness.settingsStore.issueExtractionModelPlaceholder, "Local chat model")
    }

    func test_issueExtractionModelPlaceholder_parakeetLocal_returnsNotAvailable() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .parakeetLocal

        XCTAssertEqual(harness.settingsStore.issueExtractionModelPlaceholder, "Not available")
    }
}
