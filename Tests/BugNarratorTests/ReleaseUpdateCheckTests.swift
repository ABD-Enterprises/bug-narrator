import Foundation
import XCTest
@testable import BugNarrator

/// #961: an installed app must learn a newer release exists without the user
/// going to GitHub to look. "Check for Updates" previously just opened a web
/// page, so every installed user kept their bugs until they happened to
/// re-download.
final class ReleaseUpdateCheckTests: XCTestCase {
    private struct StubFeed: LatestReleaseFeeding {
        let result: Result<LatestRelease, Error>

        func latestRelease() async throws -> LatestRelease {
            try result.get()
        }
    }

    private struct StubError: Error, LocalizedError {
        let errorDescription: String? = "the network is down"
    }

    private func release(_ tag: String) -> LatestRelease {
        LatestRelease(tag: tag, releaseURL: URL(string: "https://example.com/releases/\(tag)")!)
    }

    private func check(current: String, feed: Result<LatestRelease, Error>) async -> ReleaseUpdateOutcome {
        await ReleaseUpdateChecker(feed: StubFeed(result: feed)).check(currentVersion: current)
    }

    // MARK: - Version ordering

    func testVersionOrderingHandlesTagPrefixAndUnevenComponentCounts() {
        XCTAssertLessThan(ReleaseVersion("1.0.41")!, ReleaseVersion("v1.0.42")!)
        XCTAssertLessThan(ReleaseVersion("1.0.9")!, ReleaseVersion("1.0.10")!, "String comparison would get this backwards.")
        XCTAssertLessThan(ReleaseVersion("1.0")!, ReleaseVersion("1.0.1")!)
        XCTAssertEqual(ReleaseVersion("1.0.0")!, ReleaseVersion("v1.0.0")!)
        XCTAssertLessThan(ReleaseVersion("1.2.0")!, ReleaseVersion("1.10.0")!)
    }

    func testUnparseableVersionsAreRejectedRatherThanCoercedToZero() {
        XCTAssertNil(ReleaseVersion(""))
        XCTAssertNil(ReleaseVersion("nightly"))
        XCTAssertNotNil(ReleaseVersion("1.0.41-beta.2"), "A suffixed tag still has a usable numeric prefix.")
    }

    /// A prerelease of the same numbers must not read as newer, or a `-beta`
    /// tag would nag every user on the matching stable build.
    func testPrereleaseOfTheSameNumbersIsNotNewer() async {
        let outcome = await check(current: "1.0.42", feed: .success(release("v1.0.42-beta.1")))
        XCTAssertEqual(outcome, .upToDate(current: "1.0.42"))
    }

    // MARK: - Outcomes

    func testNewerReleaseIsReportedWithBothVersionsAndADownloadLink() async {
        let outcome = await check(current: "1.0.41", feed: .success(release("v1.0.42")))

        guard case .updateAvailable(let latest, let current, let url) = outcome else {
            return XCTFail("Expected an available update, got \(outcome)")
        }
        XCTAssertEqual(latest, "v1.0.42")
        XCTAssertEqual(current, "1.0.41")
        XCTAssertEqual(url, URL(string: "https://example.com/releases/v1.0.42")!)
        XCTAssertTrue(outcome.userMessage.contains("1.0.41"), outcome.userMessage)
    }

    func testCurrentBuildReportsUpToDate() async {
        let outcome = await check(current: "1.0.42", feed: .success(release("v1.0.42")))
        XCTAssertEqual(outcome, .upToDate(current: "1.0.42"))
    }

    /// Running ahead of the published release (a local build) is not an update.
    func testBuildNewerThanTheFeedIsNotOfferedADowngrade() async {
        let outcome = await check(current: "1.1.0", feed: .success(release("v1.0.42")))
        XCTAssertEqual(outcome, .upToDate(current: "1.1.0"))
    }

    /// The distinction that matters: a failed check is "we do not know", never
    /// "you are current". Reporting up-to-date on a network error would tell a
    /// user with a security fix waiting that they have nothing to do.
    func testUnreachableFeedIsUndeterminedNotUpToDate() async {
        let outcome = await check(current: "1.0.41", feed: .failure(StubError()))

        guard case .undetermined(let reason) = outcome else {
            return XCTFail("Expected undetermined, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("network"), reason)
    }

    // MARK: - What the button opens

    private var fallback: URL { BugNarratorLinks.releases }

    /// The guarantee the pre-#961 behavior provided: the button never
    /// dead-ends. A check that cannot complete still opens the releases page.
    func testFailedCheckStillOffersTheReleasesPage() async {
        let outcome = await check(current: "1.0.41", feed: .failure(StubError()))
        XCTAssertEqual(outcome.urlToOpen(fallback: fallback), fallback)
        XCTAssertTrue(outcome.userMessage.contains("could not check"), outcome.userMessage)
    }

    func testAvailableUpdateOpensThatReleaseNotTheGenericPage() async {
        let outcome = await check(current: "1.0.41", feed: .success(release("v1.0.42")))
        XCTAssertEqual(
            outcome.urlToOpen(fallback: fallback),
            URL(string: "https://example.com/releases/v1.0.42")!
        )
    }

    /// Nothing opens when there is nothing to do — the old button launched a
    /// browser even on the latest build.
    func testUpToDateOpensNothing() async {
        let outcome = await check(current: "1.0.41", feed: .success(release("v1.0.41")))
        XCTAssertNil(outcome.urlToOpen(fallback: fallback))
        XCTAssertEqual(outcome.userMessage, "BugNarrator 1.0.41 is the latest release.")
    }

    func testUnparseableTagIsUndetermined() async {
        let outcome = await check(current: "1.0.41", feed: .success(release("nightly")))

        guard case .undetermined = outcome else {
            return XCTFail("Expected undetermined, got \(outcome)")
        }
    }
}
