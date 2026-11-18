import Foundation
import XCTest
@testable import BugNarrator

final class ProductInfoTests: XCTestCase {
    func testHelpMenuLinkDestinations() {
        // Locks the Help menu / Support view link destinations so an accidental
        // edit to BugNarratorLinks is caught in CI.
        XCTAssertEqual(
            BugNarratorLinks.documentation.absoluteString,
            "https://github.com/SureForgeTech/sureforge-capture/blob/main/docs/UserGuide.md"
        )
        XCTAssertEqual(
            BugNarratorLinks.issues.absoluteString,
            "https://github.com/SureForgeTech/sureforge-capture/issues/new"
        )
        XCTAssertEqual(
            BugNarratorLinks.repository.absoluteString,
            "https://github.com/SureForgeTech/sureforge-capture"
        )
    }

    func testMetadataBuildsVersionDescriptionFromInfoDictionary() {
        let metadata = BugNarratorMetadata(
            infoDictionary: [
                "CFBundleDisplayName": "BugNarrator",
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45",
                "NSHumanReadableCopyright": "© 2026 SureForgeTech"
            ]
        )

        XCTAssertEqual(metadata.appName, "BugNarrator")
        XCTAssertEqual(metadata.version, "1.2.3")
        XCTAssertEqual(metadata.build, "45")
        XCTAssertEqual(metadata.versionDescription, "Version 1.2.3 (45)")
        XCTAssertEqual(metadata.copyrightLine, "© 2026 SureForgeTech")
    }

    func testMetadataFallsBackToDefaultsWhenBundleValuesAreMissing() {
        let metadata = BugNarratorMetadata(infoDictionary: [:])

        XCTAssertEqual(metadata.appName, "SureForge Capture")
        XCTAssertEqual(metadata.version, "1.0")
        XCTAssertEqual(metadata.build, "1")
        XCTAssertEqual(metadata.versionDescription, "Version 1.0 (1)")
    }

    func testProjectLinksUseExpectedPublicURLs() {
        XCTAssertEqual(BugNarratorLinks.repository.absoluteString, "https://github.com/SureForgeTech/sureforge-capture")
        XCTAssertEqual(BugNarratorLinks.documentation.absoluteString, "https://github.com/SureForgeTech/sureforge-capture/blob/main/docs/UserGuide.md")
        XCTAssertEqual(BugNarratorLinks.issues.absoluteString, "https://github.com/SureForgeTech/sureforge-capture/issues/new")
        XCTAssertEqual(BugNarratorLinks.releases.absoluteString, "https://github.com/SureForgeTech/sureforge-capture/releases")
        XCTAssertEqual(BugNarratorLinks.supportDevelopment.absoluteString, "https://www.paypal.com/donate/?hosted_button_id=FWFQ6KCZBWWH8")
    }

    func testSupportDevelopmentLinkUsesHostedPayPalPage() {
        let query = URLComponents(
            url: BugNarratorLinks.supportDevelopment,
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        XCTAssertTrue(query.contains(URLQueryItem(name: "hosted_button_id", value: "FWFQ6KCZBWWH8")))
    }

    func testChangelogHighlightsUseLatestReleaseSection() {
        let changelog = ChangelogDocument(markdown: """
        # Changelog

        ## 1.0.0

        - Added About BugNarrator.
        - Added changelog viewing.

        ## 0.9.0

        - Older release note.
        """)

        XCTAssertEqual(changelog.latestHighlights, ["Added About BugNarrator.", "Added changelog viewing."])
    }

    func testRuntimeEnvironmentDetectsLocalTestingBuildsFromDerivedData() {
        let environment = AppRuntimeEnvironment(
            bundlePath: "/tmp/DerivedData/BugNarrator/Build/Products/Debug/BugNarrator.app"
        )

        XCTAssertTrue(environment.isLocalTestingBuild)
    }

    func testRuntimeEnvironmentDoesNotTreatInstalledBuildAsLocalTestingBuild() {
        let environment = AppRuntimeEnvironment(bundlePath: "/Applications/BugNarrator.app")

        XCTAssertFalse(environment.isLocalTestingBuild)
    }
}
