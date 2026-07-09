import XCTest
@testable import BugNarrator

@MainActor
final class SettingsStoreTranscriptionInputTests: XCTestCase {
    // MARK: - normalizedLanguageHint

    func test_normalizedLanguageHint_whitespaceOnly_returnsNil() throws {
        let harness = AppStateHarness()
        harness.settingsStore.languageHint = "   \n\t  "

        XCTAssertNil(harness.settingsStore.normalizedLanguageHint)
    }

    func test_normalizedLanguageHint_leadingTrailingWhitespace_isTrimmed() throws {
        let harness = AppStateHarness()
        harness.settingsStore.languageHint = "  fr  "

        XCTAssertEqual(harness.settingsStore.normalizedLanguageHint, "fr")
    }

    func test_normalizedLanguageHint_normalValue_returnsUnchanged() throws {
        let harness = AppStateHarness()
        harness.settingsStore.languageHint = "es"

        XCTAssertEqual(harness.settingsStore.normalizedLanguageHint, "es")
    }

    // MARK: - normalizedPrompt

    func test_normalizedPrompt_whitespaceOnly_returnsNil() throws {
        let harness = AppStateHarness()
        harness.settingsStore.transcriptionPrompt = "   "

        XCTAssertNil(harness.settingsStore.normalizedPrompt)
    }

    func test_normalizedPrompt_leadingTrailingWhitespace_isTrimmed() throws {
        let harness = AppStateHarness()
        harness.settingsStore.transcriptionPrompt = "  Focus on user story keywords.  "

        XCTAssertEqual(harness.settingsStore.normalizedPrompt, "Focus on user story keywords.")
    }

    func test_normalizedPrompt_normalValue_returnsUnchanged() throws {
        let harness = AppStateHarness()
        harness.settingsStore.transcriptionPrompt = "Prefer engineering vocabulary."

        XCTAssertEqual(harness.settingsStore.normalizedPrompt, "Prefer engineering vocabulary.")
    }

    // MARK: - transcriptionRequest composition

    func test_transcriptionRequest_composesFieldsFromNormalizedAccessorsForOpenAIDefault() throws {
        let harness = AppStateHarness()
        harness.settingsStore.aiProvider = .openAI
        harness.settingsStore.preferredModel = "whisper-1"
        harness.settingsStore.languageHint = "  en  "
        harness.settingsStore.transcriptionPrompt = ""

        let request = harness.settingsStore.transcriptionRequest

        XCTAssertEqual(request.model, "whisper-1")
        XCTAssertEqual(request.languageHint, "en")
        XCTAssertNil(request.prompt)
        XCTAssertEqual(request.apiBaseURL, harness.settingsStore.openAIBaseURLValue)
    }
}
