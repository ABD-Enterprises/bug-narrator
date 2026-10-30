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

    // MARK: - Which releases count

    private func payload(
        tag: String,
        assets: [(name: String, state: String, size: Int)] = [("BugNarrator-macOS.dmg", "uploaded", 1024)],
        draft: Bool = false,
        prerelease: Bool = false,
        htmlURL: String? = nil
    ) -> [String: Any] {
        [
            "tag_name": tag,
            "html_url": htmlURL ?? "https://github.com/ABD-Enterprises/bug-narrator/releases/tag/\(tag)",
            "draft": draft,
            "prerelease": prerelease,
            "assets": assets.map { ["name": $0.name, "state": $0.state, "size": $0.size] },
        ]
    }

    /// Serves the given pages, one per requested page number. Each page is a
    /// list of release payloads, as the releases endpoint returns them.
    private func latestFrom(_ pages: [[[String: Any]]]) async throws -> LatestRelease {
        MockURLProtocol.requestHandler = { request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
            let page = Int(components?.queryItems?.first(where: { $0.name == "page" })?.value ?? "") ?? 1
            let body = page >= 1 && page <= pages.count ? pages[page - 1] : []
            let data = try JSONSerialization.data(withJSONObject: body)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        defer { MockURLProtocol.requestHandler = nil }

        let feed = GitHubLatestReleaseFeed(session: makeMockURLSession())
        return try await feed.latestRelease()
    }

    /// The transcription server publishes its own releases. One of them being
    /// the newest published release must not break the app's update check.
    func testAReleaseWithoutAMacOSAppPackageIsNotAnAppRelease() async throws {
        let server = payload(
            tag: "transcription-windows-v1.0.0",
            assets: [("bugnarrator-transcription-windows-x64.zip", "uploaded", 1024)]
        )
        let app = payload(tag: "v1.0.42")

        let latest = try await latestFrom([[server, app]])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    /// A tester release tagged like a version would be offered to everybody.
    func testAReleaseWhoseTagIsNotAVersionIsIgnored() async throws {
        let tester = payload(
            tag: "windows-tester-v1.2.0",
            assets: [("BugNarrator-windows-win-x64.zip", "uploaded", 1024)]
        )
        let app = payload(tag: "v1.0.42")

        let latest = try await latestFrom([[tester, app]])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    func testDraftsAndPrereleasesAreIgnored() async throws {
        let draft = payload(tag: "v1.0.43", draft: true)
        let prerelease = payload(tag: "v1.0.44", prerelease: true)
        let app = payload(tag: "v1.0.42")

        let latest = try await latestFrom([[draft, prerelease, app]])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    /// An upload that has not finished is not an offerable package.
    func testAnAssetThatIsNotUploadedIsIgnored() async throws {
        let partial = payload(tag: "v1.0.43", assets: [("BugNarrator-macOS.dmg", "newer", 0)])
        let app = payload(tag: "v1.0.42")

        let latest = try await latestFrom([[partial, app]])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    /// A feed that answered with a link somewhere else would send the user off
    /// the project.
    func testAReleaseLinkOffThisRepositoryIsIgnored() async throws {
        let elsewhere = payload(
            tag: "v1.0.43",
            htmlURL: "https://example.com/releases/tag/v1.0.43"
        )
        let app = payload(tag: "v1.0.42")

        let latest = try await latestFrom([[elsewhere, app]])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    func testTheHighestAppReleaseWins() async throws {
        let releases = [payload(tag: "v1.0.9"), payload(tag: "v1.0.10"), payload(tag: "v1.0.2")]

        let latest = try await latestFrom([releases])

        XCTAssertEqual(latest.tag, "v1.0.10")
    }

    /// The release list is longer than one page, and the newest app release
    /// may not be on the first page.
    func testTheSearchReadsPastTheFirstPage() async throws {
        let full = (0..<GitHubLatestReleaseFeed.pageSize).map { _ in
            payload(tag: "v0.9.\(UUID().uuidString.prefix(4))")
        }
        let second = [payload(tag: "v1.0.42")]

        let latest = try await latestFrom([full, second])

        XCTAssertEqual(latest.tag, "v1.0.42")
    }

    /// A search that cannot complete must never report up to date.
    func testNoAppReleaseAtAllIsAnErrorNotAnEmptyAnswer() async {
        do {
            _ = try await latestFrom([[payload(tag: "transcription-windows-v1.0.0", assets: [])]])
            XCTFail("Expected the search to fail")
        } catch {
            XCTAssertTrue("\(error)".contains("no compatible published macOS app release"), "\(error)")
        }
    }

    func testTheAppPackageMatcherOnlyAcceptsTheAppsOwnAssets() {
        XCTAssertTrue(GitHubLatestReleaseFeed.isMacOSAppPackage("BugNarrator-macOS.dmg"))
        XCTAssertTrue(GitHubLatestReleaseFeed.isMacOSAppPackage("BugNarrator-v1.1.0-macOS.dmg"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isMacOSAppPackage("bugnarrator-transcription-macos-arm64.dmg"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isMacOSAppPackage("BugNarrator-windows-win-x64.zip"))
    }

    func testTheVersionTagMatcherRejectsTagsThatOnlyStartLikeAVersion() {
        XCTAssertTrue(GitHubLatestReleaseFeed.isVersionTag("1.0.41"))
        XCTAssertTrue(GitHubLatestReleaseFeed.isVersionTag("v1.0.41"))
        XCTAssertTrue(GitHubLatestReleaseFeed.isVersionTag("1.0.41-beta.2"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isVersionTag("windows-tester-v1.2.0"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isVersionTag("transcription-windows-v1.0.0"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isVersionTag("v1"))
        XCTAssertFalse(GitHubLatestReleaseFeed.isVersionTag("nightly"))
    }
}
