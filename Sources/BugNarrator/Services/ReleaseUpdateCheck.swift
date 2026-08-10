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

/// Reads the repository's public `releases/latest`. Unauthenticated and
/// header-free on purpose: no token, no install id, nothing that identifies
/// who asked.
struct GitHubLatestReleaseFeed: LatestReleaseFeeding {
    private let endpoint: URL
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://api.github.com/repos/ABD-Enterprises/bug-narrator/releases/latest")!,
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
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AppError.networkFailure
                .asUpdateCheckFailure("the releases feed answered \(code)")
        }

        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard let releaseURL = URL(string: payload.htmlURL) else {
            throw AppError.networkFailure.asUpdateCheckFailure("the releases feed returned an unusable link")
        }

        return LatestRelease(tag: payload.tagName, releaseURL: releaseURL)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
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
