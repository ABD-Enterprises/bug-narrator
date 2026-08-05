import XCTest
@testable import BugNarrator

/// #910: the setup copy on the menu bar and the empty session library both told
/// the user they could start recording before finishing setup, while
/// `AppState.needsAPIKeySetup` disabled the control and `startSession` rejected
/// the attempt. These tests pin the copy to what the gate actually allows.
final class RecordingSetupCopyTests: XCTestCase {
    private let keyRequiringProviders: [AIProvider] = AIProvider.allCases.filter(\.requiresAPIKey)
    private let keylessProviders: [AIProvider] = AIProvider.allCases.filter { !$0.requiresAPIKey }

    func testNoSurfaceClaimsRecordingWorksBeforeSetup() {
        // The exact phrasings that shipped the contradiction, plus the general
        // shape of the promise, so a reworded regression is still caught.
        let forbidden = [
            "You can start recording without",
            "You can record without",
            "Recording can start now",
            "can start recording"
        ]

        for provider in AIProvider.allCases {
            let copy = [
                RecordingSetupCopy.menuBannerDescription(for: provider),
                RecordingSetupCopy.emptyLibraryDescription(for: provider)
            ]

            for text in copy {
                for phrase in forbidden {
                    XCTAssertFalse(
                        text.localizedCaseInsensitiveContains(phrase),
                        "\(provider.displayName) copy invites recording the gate refuses: \"\(text)\""
                    )
                }
            }
        }
    }

    func testEverySurfaceNamesThePrerequisiteBeforeRecording() {
        for provider in AIProvider.allCases {
            for text in [
                RecordingSetupCopy.menuBannerDescription(for: provider),
                RecordingSetupCopy.emptyLibraryDescription(for: provider)
            ] {
                XCTAssertTrue(
                    text.localizedCaseInsensitiveContains("before recording"),
                    "\(provider.displayName) copy should state the prerequisite comes first: \"\(text)\""
                )
                XCTAssertTrue(
                    text.contains(provider.displayName),
                    "Copy should name the provider it is talking about: \"\(text)\""
                )
            }
        }
    }

    func testKeyRequiringProvidersAskForAKeyAndDiscloseCost() {
        XCTAssertFalse(keyRequiringProviders.isEmpty, "Precondition: at least one provider requires a key.")

        for provider in keyRequiringProviders {
            let banner = RecordingSetupCopy.menuBannerDescription(for: provider)
            XCTAssertTrue(banner.localizedCaseInsensitiveContains("API key"))
            XCTAssertTrue(
                banner.localizedCaseInsensitiveContains("charges"),
                "Bring-your-own-key providers must keep disclosing that usage may cost money."
            )
            XCTAssertTrue(
                RecordingSetupCopy.emptyLibraryDescription(for: provider).localizedCaseInsensitiveContains("API key")
            )
        }
    }

    func testKeylessProvidersPointAtLocalSetupRatherThanAKey() {
        XCTAssertFalse(keylessProviders.isEmpty, "Precondition: at least one provider needs no key.")

        for provider in keylessProviders {
            for text in [
                RecordingSetupCopy.menuBannerDescription(for: provider),
                RecordingSetupCopy.emptyLibraryDescription(for: provider)
            ] {
                XCTAssertTrue(
                    text.localizedCaseInsensitiveContains("local server"),
                    "Keyless providers should point at local setup: \"\(text)\""
                )
                XCTAssertFalse(
                    text.localizedCaseInsensitiveContains("API key"),
                    "Keyless providers must not ask for an API key: \"\(text)\""
                )
            }
        }
    }
}
