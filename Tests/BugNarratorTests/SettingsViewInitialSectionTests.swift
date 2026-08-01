import XCTest
@testable import BugNarrator

/// Covers the Settings landing-pane rule from #911: an install with no usable
/// AI provider credential opens on `AI Engines` rather than `General`.
@MainActor
final class SettingsViewInitialSectionTests: XCTestCase {
    func testUnconfiguredInstallOpensOnAIEngines() {
        XCTAssertEqual(
            SettingsView.initialSection(hasUsableAIProviderCredential: false),
            .aiEngines,
            "A user with no usable provider credential is sent to Settings by the recording gate; they must land on the pane that resolves it."
        )
    }

    func testConfiguredInstallOpensOnGeneral() {
        XCTAssertEqual(
            SettingsView.initialSection(hasUsableAIProviderCredential: true),
            .general,
            "Once a provider is configured, Settings keeps its established General landing pane."
        )
    }
}
