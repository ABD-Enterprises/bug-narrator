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
}
