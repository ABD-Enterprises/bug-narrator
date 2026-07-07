import XCTest
@testable import BugNarrator

final class ChangelogDocumentTests: XCTestCase {
    func testLatestHighlightsUseOnlyFirstReleaseSectionAndCapAtThreeItems() {
        let changelog = ChangelogDocument(markdown: """
        # Changelog

        Introductory copy.

        ## 1.0.2

        - First current highlight.
        - Second current highlight.
        - Third current highlight.
        - Fourth current highlight.

        ## 1.0.1

        - Previous highlight.
        """)

        XCTAssertEqual(
            changelog.latestHighlights,
            [
                "First current highlight.",
                "Second current highlight.",
                "Third current highlight."
            ]
        )
    }

    func testLatestHighlightsIgnoreContentBeforeFirstReleaseSection() {
        let changelog = ChangelogDocument(markdown: """
        # Changelog

        - Project overview bullet.

        ## 1.0.0

        Release prose.
        - Shipped baseline release.
        """)

        XCTAssertEqual(changelog.latestHighlights, ["Shipped baseline release."])
    }

    func testReleasesSkipEmptySectionsAndParseCategoryPrefixes() {
        let changelog = ChangelogDocument(markdown: """
        # Changelog

        ## Unreleased

        ## 1.0.2 - 2026-07-07

        - [FIX] Made the changelog readable.
        - [INTERNAL] Added parser coverage.

        ## 1.0.1

        - Previous note.
        """)

        XCTAssertEqual(changelog.releases.map(\.title), ["1.0.2 - 2026-07-07", "1.0.1"])
        XCTAssertEqual(changelog.releases.first?.version, "1.0.2")
        XCTAssertEqual(changelog.releases.first?.date, "2026-07-07")
        XCTAssertEqual(changelog.releases.first?.notes.first?.category, "FIX")
        XCTAssertEqual(changelog.releases.first?.notes.first?.text, "Made the changelog readable.")
        XCTAssertEqual(changelog.latestHighlights, ["Made the changelog readable.", "Added parser coverage."])
    }
}
