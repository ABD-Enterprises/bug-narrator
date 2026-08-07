import XCTest
@testable import BugNarrator

/// #912: `autoExtractIssues` stays off by default, because turning it on would
/// spend the user's provider credit on every session without asking. Instead a
/// one-time offer surfaces the feature after the first transcript.
///
/// These cover the decision and the one-time persistence. The rule that matters
/// most is the provider one: extraction must never be offered on a
/// transcription-only provider that cannot perform it.
@MainActor
final class IssueExtractionOfferTests: XCTestCase {
    // MARK: - Pure decision

    func testOffersOnFreshInstallWithACapableProvider() {
        XCTAssertTrue(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: false,
                hasOffered: false,
                supportsIssueExtraction: true
            )
        )
    }

    func testDoesNotOfferTwice() {
        XCTAssertFalse(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: false,
                hasOffered: true,
                supportsIssueExtraction: true
            ),
            "Declining must be durable — a user who ignored the offer should not be asked again every session."
        )
    }

    func testDoesNotOfferWhenExtractionIsAlreadyOn() {
        XCTAssertFalse(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: true,
                hasOffered: false,
                supportsIssueExtraction: true
            ),
            "Nothing to offer when the pipeline already extracts automatically."
        )
    }

    func testNeverOffersOnATranscriptionOnlyProvider() {
        for hasOffered in [true, false] {
            XCTAssertFalse(
                SettingsStore.shouldOfferIssueExtraction(
                    autoExtractIssues: false,
                    hasOffered: hasOffered,
                    supportsIssueExtraction: false
                ),
                "Offering extraction on a provider that cannot extract is a dead end — the same class of defect #910 removed."
            )
        }
    }

    // MARK: - Wiring against a real SettingsStore

    func testParakeetIsTreatedAsIncapable() {
        let harness = AppStateHarness(apiKey: "")
        harness.settingsStore.aiProvider = .parakeetLocal

        XCTAssertFalse(
            harness.settingsStore.supportsIssueExtraction,
            "Precondition: Local (Parakeet) is transcription-only."
        )
        XCTAssertFalse(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: harness.settingsStore.autoExtractIssues,
                hasOffered: harness.settingsStore.hasOfferedIssueExtraction,
                supportsIssueExtraction: harness.settingsStore.supportsIssueExtraction
            )
        )
    }

    func testOpenAIIsTreatedAsCapableAndOffersOnce() {
        let harness = AppStateHarness(apiKey: "sk-test-123")
        harness.settingsStore.aiProvider = .openAI

        XCTAssertTrue(harness.settingsStore.supportsIssueExtraction)
        XCTAssertFalse(
            harness.settingsStore.hasOfferedIssueExtraction,
            "Precondition: a fresh store has not made the offer."
        )

        XCTAssertTrue(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: harness.settingsStore.autoExtractIssues,
                hasOffered: harness.settingsStore.hasOfferedIssueExtraction,
                supportsIssueExtraction: harness.settingsStore.supportsIssueExtraction
            )
        )

        harness.settingsStore.markIssueExtractionOffered()

        XCTAssertTrue(harness.settingsStore.hasOfferedIssueExtraction)
        XCTAssertFalse(
            SettingsStore.shouldOfferIssueExtraction(
                autoExtractIssues: harness.settingsStore.autoExtractIssues,
                hasOffered: harness.settingsStore.hasOfferedIssueExtraction,
                supportsIssueExtraction: harness.settingsStore.supportsIssueExtraction
            ),
            "Once marked, the offer must not recur."
        )
    }

    func testMarkingIsIdempotent() {
        let harness = AppStateHarness(apiKey: "sk-test-123")
        harness.settingsStore.markIssueExtractionOffered()
        harness.settingsStore.markIssueExtractionOffered()

        XCTAssertTrue(harness.settingsStore.hasOfferedIssueExtraction)
    }

    // MARK: - Default preserved

    func testAutoExtractRemainsOffByDefault() {
        let harness = AppStateHarness(apiKey: "sk-test-123")

        XCTAssertFalse(
            harness.settingsStore.autoExtractIssues,
            "#912 deliberately does NOT flip this default — that would spend provider credit without asking."
        )
    }
}
