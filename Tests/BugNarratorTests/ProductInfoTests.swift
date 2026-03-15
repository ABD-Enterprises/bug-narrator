import Foundation
import XCTest
@testable import BugNarrator

final class ProductInfoTests: XCTestCase {
    func testMetadataBuildsVersionDescriptionFromInfoDictionary() {
        let metadata = BugNarratorMetadata(
            infoDictionary: [
                "CFBundleDisplayName": "BugNarrator",
                "CFBundleShortVersionString": "1.2.3",
                "CFBundleVersion": "45",
                "NSHumanReadableCopyright": "© 2026 ABD Enterprises"
            ]
        )

        XCTAssertEqual(metadata.appName, "BugNarrator")
        XCTAssertEqual(metadata.version, "1.2.3")
        XCTAssertEqual(metadata.build, "45")
        XCTAssertEqual(metadata.versionDescription, "Version 1.2.3 (45)")
        XCTAssertEqual(metadata.copyrightLine, "© 2026 ABD Enterprises")
    }

    func testMetadataFallsBackToDefaultsWhenBundleValuesAreMissing() {
        let metadata = BugNarratorMetadata(infoDictionary: [:])

        XCTAssertEqual(metadata.appName, "BugNarrator")
        XCTAssertEqual(metadata.version, "1.0")
        XCTAssertEqual(metadata.build, "1")
        XCTAssertEqual(metadata.versionDescription, "Version 1.0 (1)")
    }

    func testProjectLinksUseExpectedPublicURLs() {
        XCTAssertEqual(BugNarratorLinks.repository.absoluteString, "https://github.com/deffenda/bugnarrator")
        XCTAssertEqual(BugNarratorLinks.documentation.absoluteString, "https://github.com/deffenda/bugnarrator/blob/main/docs/UserGuide.md")
        XCTAssertEqual(BugNarratorLinks.issues.absoluteString, "https://github.com/deffenda/bugnarrator/issues/new")
        XCTAssertEqual(BugNarratorLinks.releases.absoluteString, "https://github.com/deffenda/bugnarrator/releases")
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
            bundlePath: "/Users/deffenda/Library/Developer/Xcode/DerivedData/BugNarrator/Build/Products/Debug/BugNarrator.app"
        )

        XCTAssertTrue(environment.isLocalTestingBuild)
    }

    func testRuntimeEnvironmentDoesNotTreatInstalledBuildAsLocalTestingBuild() {
        let environment = AppRuntimeEnvironment(bundlePath: "/Applications/BugNarrator.app")

        XCTAssertFalse(environment.isLocalTestingBuild)
    }
}
