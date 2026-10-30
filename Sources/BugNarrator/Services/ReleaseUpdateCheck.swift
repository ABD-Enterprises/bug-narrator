import Foundation

/// Learning that a newer build exists, without the user going to look (#961).
///
/// Before this, "Check for Updates" opened the releases web page and nothing
/// else existed — no appcast, no launch-time check. An installed user kept
/// their bugs, and any future security fix, until they happened to re-download.
///
/// Deliberately small: a read of the public releases endpoint and a version
/// comparison. No Sparkle, no background polling, no identifiers — the request
/// carries nothing about the user, so the check cannot become telemetry.
struct ReleaseVersion: Comparable, Equatable, CustomStringConvertible {
    let components: [Int]
    let raw: String

    var description: String { raw }

    /// Accepts `1.0.41`, `v1.0.41`, and trailing suffixes like `1.0.41-beta.2`
    /// (the suffix is ignored for ordering — a prerelease of the same numbers
    /// is not treated as newer, which keeps a `-beta` tag from nagging users on
    /// the matching stable build).
    init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let numericPart = withoutPrefix.prefix { $0.isNumber || $0 == "." }
        let parsed = numericPart
            .split(separator: ".", omittingEmptySubsequences: true)
            .compactMap { Int($0) }

        guard !parsed.isEmpty else { return nil }
        components = parsed
        raw = trimmed
    }

    /// Compares the numbers, not the text. `1.0.0` and `v1.0.0` are the same
    /// release; `raw` is kept only so messages echo the tag the user will see.
    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

enum ReleaseUpdateOutcome: Equatable {
    case upToDate(current: String)
    case updateAvailable(latest: String, current: String, releaseURL: URL)
    /// The check could not be completed. Never rendered as "up to date" — not
    /// knowing and being current are different answers.
    case undetermined(reason: String)

    /// Which page, if any, the check should open. Kept here rather than in the
    /// controller so the "never dead-ends" rule is a pure, tested decision
    /// instead of a side effect buried next to NSWorkspace.
    ///
    /// - up to date: nothing. The old button launched a browser even when
    ///   there was nothing to do.
    /// - update available: that release.
    /// - undetermined: the releases page, preserving the pre-#961 behavior so
    ///   a failed check still gives the user somewhere to go.
    func urlToOpen(fallback: URL) -> URL? {
        switch self {
        case .upToDate:
            return nil
        case .updateAvailable(_, _, let releaseURL):
            return releaseURL
        case .undetermined:
            return fallback
        }
    }

    var userMessage: String {
        switch self {
        case .upToDate(let current):
            return "BugNarrator \(current) is the latest release."
        case .updateAvailable(let latest, let current, _):
            return "BugNarrator \(latest) is available — you are on \(current). Opening the download page."
        case .undetermined(let reason):
            return "BugNarrator could not check for updates: \(reason)"
        }
    }
}

struct LatestRelease: Equatable {
    let tag: String
    let releaseURL: URL
}

protocol LatestReleaseFeeding: Sendable {
    func latestRelease() async throws -> LatestRelease
}

/// Reads the repository's public releases and finds the newest one that is
/// actually a macOS app release.
///
/// The check used to read `releases/latest`, which is the most recent
/// non-draft, non-prerelease release of any kind. The transcription server
/// and the Windows tester publish their own releases, so the moment either of
/// them published one, "Check for Updates" stopped working for every macOS
/// user — and a tester release tagged `v1.2.0` would have been offered to
/// everybody as the app. The Windows port already searches the release list
/// for a published app package that matches the running architecture; this
/// does the same for macOS.
///
/// Unauthenticated and header-free on purpose: no token, no install id,
/// nothing that identifies who asked.
struct GitHubLatestReleaseFeed: LatestReleaseFeeding {
    /// How many releases the search asks for per page.
    static let pageSize = 30

    /// How many pages the search may read before it gives up. The list is
    /// ordered newest first, so this covers a long tail of releases.
    static let maxPages = 20

    /// How long the whole search may take, not just one request.
    static let searchTimeout: TimeInterval = 10

    /// Whether an asset belongs to a macOS app release.
    ///
    /// The app publishes `BugNarrator-macOS.dmg` and
    /// `BugNarrator-v<version>-macOS.dmg`. The transcription server publishes
    /// `bugnarrator-transcription-macos-arm64.dmg`, which is a different
    /// release with its own cadence.
    static func isMacOSAppPackage(_ name: String) -> Bool {
        name.hasPrefix("BugNarrator-") && name.hasSuffix("-macOS.dmg")
    }

    /// Whether the whole tag is a version.
    ///
    /// `ReleaseVersion` reads a numeric prefix, which is right for a build's
    /// own version but wrong for a release tag: `windows-tester-v1.2.0` would
    /// otherwise parse as 1.2.0 and be offered to every user.
    static func isVersionTag(_ tag: String) -> Bool {
        var trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }

        var core = trimmed
        if let marker = trimmed.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            let suffix = trimmed[trimmed.index(after: marker)...]
            if suffix.isEmpty { return false }
            core = String(trimmed[..<marker])
        }

        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(components.count) else { return false }
        return components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy { $0.isASCII && $0.isNumber }
        }
    }

    /// Whether the link points at this repository's release page. A feed that
    /// answered with a link somewhere else would send the user off the
    /// project, so the link is checked rather than trusted.
    static func isTrustedReleaseLink(_ url: URL, tag: String) -> Bool {
        guard url.host == "github.com" else { return false }
        return url.path == "/ABD-Enterprises/bug-narrator/releases/tag/\(tag)"
    }

    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.github.com/repos/ABD-Enterprises/bug-narrator/releases")!,
        session: URLSession? = nil
    ) {
        self.endpoint = endpoint
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    func latestRelease() async throws -> LatestRelease {
        // Bound the whole search, not just each request. Never report
        // up-to-date from an incomplete search.
        let deadline = Date().addingTimeInterval(Self.searchTimeout)
        var latest: LatestRelease?
        var latestVersion: ReleaseVersion?

        for page in 1...Self.maxPages {
            guard Date() < deadline else {
                throw AppError.networkFailure
                    .asUpdateCheckFailure("the macOS app release search timed out")
            }

            let releases = try await fetchPage(page)
            for release in releases {
                guard !release.draft,
                      !release.prerelease,
                      release.assets.contains(where: {
                          $0.state == "uploaded" && $0.size > 0 && Self.isMacOSAppPackage($0.name)
                      }),
                      Self.isVersionTag(release.tagName),
                      let releaseURL = URL(string: release.htmlURL),
                      Self.isTrustedReleaseLink(releaseURL, tag: release.tagName),
                      let version = ReleaseVersion(release.tagName) else {
                    continue
                }

                if latestVersion == nil || version > latestVersion! {
                    latestVersion = version
                    latest = LatestRelease(tag: release.tagName, releaseURL: releaseURL)
                }
            }

            if releases.count < Self.pageSize {
                guard let latest else {
                    throw AppError.networkFailure
                        .asUpdateCheckFailure("no compatible published macOS app release was found")
                }
                return latest
            }
        }

        throw AppError.networkFailure
            .asUpdateCheckFailure("the macOS app release search reached its limit; check the project releases")
    }

    private func fetchPage(_ page: Int) async throws -> [GitHubReleasePayload] {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AppError.networkFailure.asUpdateCheckFailure("the releases feed is unusable")
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: String(Self.pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = components.url else {
            throw AppError.networkFailure.asUpdateCheckFailure("the releases feed is unusable")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.networkFailure
                .asUpdateCheckFailure("the releases feed answered \(code)")
        }

        return try JSONDecoder().decode([GitHubReleasePayload].self, from: data)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(String.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([GitHubReleaseAsset].self, forKey: .assets) ?? []
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let state: String
    let size: Int

    private enum CodingKeys: String, CodingKey {
        case name
        case state
        case size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
    }
}

extension AppError {
    func asUpdateCheckFailure(_ reason: String) -> AppError {
        .diagnosticsFailure(reason)
    }
}

/// The testable half: everything except opening a browser.
struct ReleaseUpdateChecker {
    private let feed: any LatestReleaseFeeding

    init(feed: any LatestReleaseFeeding = GitHubLatestReleaseFeed()) {
        self.feed = feed
    }

    func check(currentVersion: String) async -> ReleaseUpdateOutcome {
        guard let current = ReleaseVersion(currentVersion) else {
            return .undetermined(reason: "this build does not report a readable version")
        }

        let latest: LatestRelease
        do {
            latest = try await feed.latestRelease()
        } catch let error as AppError {
            return .undetermined(reason: error.errorDescription ?? "the releases feed is unreachable")
        } catch {
            return .undetermined(reason: error.localizedDescription)
        }

        guard let latestVersion = ReleaseVersion(latest.tag) else {
            return .undetermined(reason: "the latest release tag '\(latest.tag)' is not a version")
        }

        guard current < latestVersion else {
            return .upToDate(current: current.raw)
        }

        return .updateAvailable(
            latest: latestVersion.raw,
            current: current.raw,
            releaseURL: latest.releaseURL
        )
    }
}
