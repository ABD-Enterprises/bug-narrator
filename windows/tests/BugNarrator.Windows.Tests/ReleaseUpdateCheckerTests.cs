using System.Net;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.Json;
using BugNarrator.Windows.Services.Shell;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The same fixture pairs Tests/BugNarratorTests/ReleaseUpdateCheckTests.swift uses, so the two
/// checkers cannot disagree about what counts as newer or what a failed check means.
/// </summary>
public sealed class ReleaseUpdateCheckerTests
{
    private const string Fallback = BugNarratorLinks.Releases;

    [Theory]
    [InlineData("1.0.41", "v1.0.42")]
    [InlineData("1.0.9", "1.0.10")]   // string comparison would get this backwards
    [InlineData("1.0", "1.0.1")]
    [InlineData("1.2.0", "1.10.0")]
    public void VersionOrdering_HandlesTagPrefixAndUnevenComponentCounts(string older, string newer)
    {
        Assert.True(ReleaseVersion.Parse(older)! < ReleaseVersion.Parse(newer)!);
    }

    [Fact]
    public void VersionEquality_IgnoresTheTagPrefix()
    {
        Assert.Equal(ReleaseVersion.Parse("1.0.0"), ReleaseVersion.Parse("v1.0.0"));
        Assert.Equal(ReleaseVersion.Parse("1.0").GetHashCode(), ReleaseVersion.Parse("1.0.0").GetHashCode());
    }

    [Fact]
    public void UnparseableVersions_AreRejectedRatherThanCoercedToZero()
    {
        Assert.Null(ReleaseVersion.Parse(""));
        Assert.Null(ReleaseVersion.Parse("nightly"));
        Assert.NotNull(ReleaseVersion.Parse("1.0.41-beta.2")); // a suffixed tag still has a usable numeric prefix
    }

    [Fact]
    public async Task PrereleaseOfTheSameNumbers_IsNotNewer()
    {
        var outcome = await CheckAsync("1.0.42", Release("v1.0.42-beta.1"));

        Assert.Equal(ReleaseUpdateOutcome.UpToDate("1.0.42"), outcome);
    }

    [Fact]
    public async Task NewerRelease_IsReportedWithBothVersionsAndADownloadLink()
    {
        var outcome = await CheckAsync("1.0.41", Release("v1.0.42"));

        Assert.Equal(ReleaseUpdateOutcomeKind.UpdateAvailable, outcome.Kind);
        Assert.Equal("v1.0.42", outcome.Latest);
        Assert.Equal("1.0.41", outcome.Current);
        Assert.Equal(ReleaseUrl("v1.0.42"), outcome.ReleaseUrl);
        Assert.Contains("1.0.41", outcome.UserMessage);
        Assert.Equal(ReleaseUrl("v1.0.42"), outcome.UrlToOpen(Fallback));
    }

    [Fact]
    public async Task CurrentBuild_ReportsUpToDateAndOpensNothing()
    {
        var outcome = await CheckAsync("1.0.41", Release("v1.0.41"));

        Assert.Equal(ReleaseUpdateOutcome.UpToDate("1.0.41"), outcome);
        Assert.Null(outcome.UrlToOpen(Fallback));
        Assert.Equal("BugNarrator 1.0.41 is the latest release.", outcome.UserMessage);
    }

    [Fact]
    public async Task BuildNewerThanTheFeed_IsNotOfferedADowngrade()
    {
        var outcome = await CheckAsync("1.1.0", Release("v1.0.42"));

        Assert.Equal(ReleaseUpdateOutcome.UpToDate("1.1.0"), outcome);
    }

    [Fact]
    public async Task UnreachableFeed_IsUndeterminedNotUpToDateAndStillOffersTheReleasesPage()
    {
        // A failed check is "we do not know", never "you are current".
        var outcome = await CheckAsync("1.0.41", new HttpRequestException("no route to host"));

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains("network", outcome.Reason);
        Assert.Equal(Fallback, outcome.UrlToOpen(Fallback));
        Assert.Contains("could not check", outcome.UserMessage);
    }

    [Fact]
    public async Task ClientTimeout_IsUndeterminedAndStillOffersTheReleasesPage()
    {
        // HttpClient.Timeout surfaces as a TaskCanceledException; that is a network failure, not a caller cancel.
        var outcome = await CheckAsync("1.0.41", new TaskCanceledException("The request was canceled due to the configured HttpClient.Timeout"));

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains("timed out", outcome.Reason);
        Assert.Equal(Fallback, outcome.UrlToOpen(Fallback));
    }

    [Fact]
    public async Task AnyOtherFeedFailure_IsUndeterminedAndStillOffersTheReleasesPage()
    {
        var outcome = await CheckAsync("1.0.41", new IOException("connection reset while reading"));

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Equal(Fallback, outcome.UrlToOpen(Fallback));
    }

    [Fact]
    public async Task CallerCancellation_Propagates()
    {
        using var cancellation = new CancellationTokenSource();
        var handler = new FakeHandler(_ => { cancellation.Cancel(); throw new OperationCanceledException(cancellation.Token); });
        var checker = new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler)));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => checker.CheckAsync("1.0.41", cancellation.Token));
    }

    [Theory]
    [InlineData(HttpStatusCode.NotFound, "answered 404")]
    [InlineData(HttpStatusCode.Forbidden, "answered 403")]
    public async Task NonSuccessStatus_IsUndeterminedWithTheCode(HttpStatusCode status, string expectedReason)
    {
        var outcome = await CheckAsync("1.0.41", new HttpResponseMessage(status));

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains(expectedReason, outcome.Reason);
    }

    [Theory]
    [InlineData("{\"tag_name\":\"nightly\",\"html_url\":\"https://example.com/r\"}")]
    [InlineData("{\"tag_name\":\"v1.0.42\",\"html_url\":\"not a url\"}")]
    [InlineData("{\"tag_name\":\"v1.0.42\",\"html_url\":\"javascript:alert(1)\"}")]
    [InlineData("{\"html_url\":\"https://example.com/r\"}")]
    [InlineData("this is not json")]
    public async Task UnusableFeedPayload_IsUndetermined(string body)
    {
        var outcome = await CheckAsync("1.0.41", Json(body));

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Equal(Fallback, outcome.UrlToOpen(Fallback));
    }

    [Fact]
    public async Task UnreadableCurrentVersion_IsUndeterminedWithoutTouchingTheFeed()
    {
        var handler = new FakeHandler(_ => throw new InvalidOperationException("the feed must not be called"));
        var checker = new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler)));

        var outcome = await checker.CheckAsync("nightly");

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Equal(0, handler.Calls);
    }

    [Fact]
    public async Task Feed_SendsNothingThatIdentifiesTheUser()
    {
        HttpRequestMessage? sent = null;
        var handler = new FakeHandler(request => { sent = request; return Json(Release("v1.0.42").Body); });
        await new GitHubLatestReleaseFeed(new HttpClient(handler), Architecture.X64).GetLatestReleaseAsync();

        Assert.Equal(GitHubLatestReleaseFeed.Endpoint + "?per_page=30&page=1", sent!.RequestUri!.AbsoluteUri);
        Assert.Null(sent.Headers.Authorization);
        Assert.Equal(["Accept", "User-Agent"], sent.Headers.Select(header => header.Key).OrderBy(key => key));
    }

    [Fact]
    public void UserMessages_StayAlignedWithMacWhileTheFeedSelectsWindowsPackages()
    {
        var swift = File.ReadAllText(Path.Combine(RepositoryRoot(), "Sources", "BugNarrator", "Services", "ReleaseUpdateCheck.swift"));

        Assert.DoesNotContain("/latest", GitHubLatestReleaseFeed.Endpoint, StringComparison.Ordinal);
        Assert.Contains("\"BugNarrator \\(current) is the latest release.\"", swift, StringComparison.Ordinal);
    }

    [Fact]
    public void CurrentVersion_IsTheRepoVersionFile()
    {
        // windows/src/Directory.Build.props stamps VERSION into every Windows assembly (#1184);
        // the SDK's +sha build metadata is stripped before comparing with the feed.
        var expected = File.ReadAllText(Path.Combine(RepositoryRoot(), "VERSION")).Trim();

        Assert.Equal(expected, ReleaseUpdateChecker.CurrentVersion());
        Assert.NotNull(ReleaseVersion.Parse(expected));
    }

    [Fact]
    public void CheckForUpdatesEntry_IsAnActionAfterSupportDevelopment()
    {
        Assert.Equal(TrayMenuEntryKind.Action, TrayPresentationState.CheckForUpdatesEntry.Kind);
        Assert.Equal("Check for Updates", TrayPresentationState.CheckForUpdatesEntry.Label);
        Assert.Equal("Support Development", TrayPresentationState.SupportEntries[^1].Label);
    }

    [Theory]
    [InlineData(Architecture.X64, "BugNarrator-windows-win-x64.zip")]
    [InlineData(Architecture.Arm64, "BugNarrator-windows-win-arm64.zip")]
    public async Task Feed_SelectsOnlyPublishedPackagesForTheProcessArchitecture(Architecture architecture, string asset)
    {
        var body = JsonSerializer.Serialize(new[]
        {
            ReleasePayload("v9.0.0", "BugNarrator-macOS.dmg"),
            ReleasePayload("transcription-windows-v9.0.0", "bugnarrator-transcription-windows-x64.zip"),
            ReleasePayload("v8.0.0", asset, draft: true),
            ReleasePayload("v7.0.0", asset, prerelease: true),
            ReleasePayload("windows-tester-v1.2.0", asset),
            ReleasePayload("v6.0.0", asset, state: "starter"),
            ReleasePayload("v5.0.0", asset, size: 0),
        });
        var feed = new GitHubLatestReleaseFeed(new HttpClient(new FakeHandler(_ => Json(body))), architecture);

        var latest = await feed.GetLatestReleaseAsync();
        var outcome = await new ReleaseUpdateChecker(feed).CheckAsync("1.1.0");

        Assert.Equal("windows-tester-v1.2.0", latest.Tag);
        Assert.Equal("v1.2.0", latest.Version);
        Assert.Equal(ReleaseUpdateOutcomeKind.UpdateAvailable, outcome.Kind);
        Assert.Equal("v1.2.0", outcome.Latest);
        Assert.Equal(ReleaseUrl(latest.Tag), outcome.ReleaseUrl);
    }

    [Theory]
    [InlineData("BugNarrator-macOS.dmg")]
    [InlineData("bugnarrator-transcription-windows-x64.zip")]
    [InlineData("BugNarrator-windows-win-arm64.zip")]
    [InlineData("BugNarrator-windows-win-x64.zip.sha256")]
    public async Task NoCompatibleAppRelease_IsUndeterminedRatherThanUpToDate(string asset)
    {
        var outcome = await CheckAsync("1.1.0", Json(JsonSerializer.Serialize(new[] { ReleasePayload("v9.0.0", asset) })));
        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains("no compatible published Windows app", outcome.Reason);
        Assert.Equal(Fallback, outcome.UrlToOpen(Fallback));
    }

    [Theory]
    [InlineData("http://github.com/ABD-Enterprises/bug-narrator/releases/tag/v9.0.0")]
    [InlineData("https://example.com/ABD-Enterprises/bug-narrator/releases/tag/v9.0.0")]
    [InlineData("https://github.com/other/project/releases/tag/v9.0.0")]
    [InlineData("https://user@github.com/ABD-Enterprises/bug-narrator/releases/tag/v9.0.0")]
    [InlineData("https://github.com:8443/ABD-Enterprises/bug-narrator/releases/tag/v9.0.0")]
    [InlineData("https://github.com/ABD-Enterprises/bug-narrator/releases/tag/v8.0.0")]
    [InlineData("https://github.com/ABD-Enterprises/bug-narrator/releases/tag/v9.0.0?redirect=elsewhere")]
    [InlineData("javascript:alert(1)")]
    public async Task Feed_SkipsUntrustedOrMismatchedReleaseLinks(string url)
    {
        var body = JsonSerializer.Serialize(new[] { ReleasePayload("v9.0.0", url: url), ReleasePayload("v1.2.0") });
        var outcome = await CheckAsync("1.1.0", Json(body));
        Assert.Equal(ReleaseUpdateOutcomeKind.UpdateAvailable, outcome.Kind);
        Assert.Equal(ReleaseUrl("v1.2.0"), outcome.ReleaseUrl);
    }

    [Theory]
    [InlineData("transcription-windows-v9.0.0")]
    [InlineData("nightly")]
    [InlineData("v9..0")]
    [InlineData("v9.999999999999999999999.0")]
    public async Task Feed_SkipsNonAppOrMalformedVersionTags(string tag)
    {
        var body = JsonSerializer.Serialize(new[] { ReleasePayload(tag), ReleasePayload("v1.2.0") });
        Assert.Equal("v1.2.0", (await CheckAsync("1.1.0", Json(body))).Latest);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task Feed_SearchesLaterPagesAndChoosesHighestVersionRatherThanListOrder(bool firstPageHasWindowsRelease)
    {
        var firstPage = Enumerable.Range(0, GitHubLatestReleaseFeed.PageSize)
            .Select(_ => firstPageHasWindowsRelease ? ReleasePayload("v1.2.0")
                : ReleasePayload("v9.0.0", "BugNarrator-macOS.dmg")).ToArray();
        var handler = new FakeHandler(request =>
        {
            Assert.Equal($"{GitHubLatestReleaseFeed.Endpoint}?per_page=30&page=", request.RequestUri!.AbsoluteUri[..^1]);
            return request.RequestUri.Query.EndsWith("page=1", StringComparison.Ordinal)
                ? Json(JsonSerializer.Serialize(firstPage))
                : Json(JsonSerializer.Serialize(new[] { ReleasePayload("v1.1.0"), ReleasePayload("v1.10.0") }));
        });

        var outcome = await new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler), Architecture.X64))
            .CheckAsync("1.2.0");

        Assert.Equal(2, handler.Calls);
        Assert.Equal("v1.10.0", outcome.Latest);
    }

    [Fact]
    public async Task Feed_PaginationFailureDoesNotClaimUpToDateFromPartialResults()
    {
        var firstPage = Enumerable.Range(0, GitHubLatestReleaseFeed.PageSize).Select(_ => ReleasePayload("v1.0.0"));
        var handler = new FakeHandler(request => request.RequestUri!.Query.EndsWith("page=1", StringComparison.Ordinal)
            ? Json(JsonSerializer.Serialize(firstPage)) : new HttpResponseMessage(HttpStatusCode.Forbidden));

        var outcome = await new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler), Architecture.X64))
            .CheckAsync("1.1.0");

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains("answered 403", outcome.Reason);
        Assert.Equal(2, handler.Calls);
    }

    [Fact]
    public async Task Feed_BoundsPaginationAndDoesNotTreatTheSearchLimitAsSuccess()
    {
        var page = JsonSerializer.Serialize(Enumerable.Range(0, GitHubLatestReleaseFeed.PageSize).Select(_ => ReleasePayload("v1.0.0")));
        var handler = new FakeHandler(_ => Json(page));

        var outcome = await new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler), Architecture.X64))
            .CheckAsync("1.1.0");

        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Contains("limit", outcome.Reason);
        Assert.Equal(GitHubLatestReleaseFeed.MaxPages, handler.Calls);
    }

    [Fact]
    public async Task UnsupportedArchitecture_IsUndeterminedWithoutNetworkAccess()
    {
        var handler = new FakeHandler(_ => throw new InvalidOperationException("Must not fetch"));
        var outcome = await new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(handler), Architecture.X86))
            .CheckAsync("1.1.0");
        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, outcome.Kind);
        Assert.Equal(0, handler.Calls);
    }

    [Theory]
    [InlineData("[]")]
    [InlineData("[null]")]
    [InlineData("[{\"tag_name\":\"v9.0.0\"}]")]
    public async Task MissingReleaseOrAssetMetadata_IsUndetermined(string body)
    {
        Assert.Equal(ReleaseUpdateOutcomeKind.Undetermined, (await CheckAsync("1.1.0", Json(body))).Kind);
    }

    [Fact]
    public async Task Feed_AcceptsEscapedVersionTagLinksWithoutTreatingBuildMetadataAsNewer()
    {
        var body = JsonSerializer.Serialize(new[]
        {
            ReleasePayload("windows-tester-v1.2.0+build.1", url: ReleaseUrl("windows-tester-v1.2.0%2Bbuild.1")),
        });
        var outcome = await CheckAsync("1.2.0", Json(body));
        Assert.Equal(ReleaseUpdateOutcomeKind.UpToDate, outcome.Kind);
    }

    private static string ReleaseUrl(string tag) =>
        $"https://github.com/ABD-Enterprises/bug-narrator/releases/tag/{tag}";

    private static object ReleasePayload(
        string tag,
        string asset = "BugNarrator-windows-win-x64.zip",
        bool draft = false,
        bool prerelease = false,
        string? url = null,
        string state = "uploaded",
        long size = 100) => new
        {
            tag_name = tag,
            html_url = url ?? ReleaseUrl(tag),
            draft,
            prerelease,
            assets = new[] { new { name = asset, state, size } },
        };

    private static (string Body, string Tag) Release(string tag) =>
        (JsonSerializer.Serialize(new[] { ReleasePayload(tag) }), tag);

    private static HttpResponseMessage Json(string body) =>
        new(HttpStatusCode.OK) { Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json") };

    private static Task<ReleaseUpdateOutcome> CheckAsync(string current, (string Body, string Tag) release) =>
        CheckAsync(current, Json(release.Body));

    private static Task<ReleaseUpdateOutcome> CheckAsync(string current, HttpResponseMessage response) =>
        new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(new FakeHandler(_ => response)), Architecture.X64)).CheckAsync(current);

    private static Task<ReleaseUpdateOutcome> CheckAsync(string current, Exception failure) =>
        new ReleaseUpdateChecker(new GitHubLatestReleaseFeed(new HttpClient(new FakeHandler(_ => throw failure)))).CheckAsync(current);

    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        public int Calls { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(respond(request));
        }
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        return Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourceFilePath)!, "..", "..", ".."));
    }
}
