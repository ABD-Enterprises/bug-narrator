using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BugNarrator.Windows.Services.Shell;

/// <summary>
/// A release version compared by its numbers, not its text. Mirrors macOS ReleaseVersion
/// (Services/ReleaseUpdateCheck.swift): accepts 1.0.41, v1.0.41, and suffixed tags such as
/// 1.0.41-beta.2 (the suffix is ignored for ordering, so a prerelease of the same numbers is not
/// treated as newer). Missing trailing components count as zero, so 1.0 == 1.0.0.
/// </summary>
public sealed class ReleaseVersion : IComparable<ReleaseVersion>, IEquatable<ReleaseVersion>
{
    public IReadOnlyList<int> Components { get; }

    /// <summary>The trimmed tag as the user will see it; kept for messages only.</summary>
    public string Raw { get; }

    private ReleaseVersion(IReadOnlyList<int> components, string raw)
    {
        Components = components;
        Raw = raw;
    }

    public static ReleaseVersion? Parse(string? value)
    {
        var trimmed = value?.Trim() ?? string.Empty;
        var withoutPrefix = trimmed.StartsWith('v') || trimmed.StartsWith('V') ? trimmed[1..] : trimmed;
        var numericLength = 0;
        while (numericLength < withoutPrefix.Length
               && (char.IsAsciiDigit(withoutPrefix[numericLength]) || withoutPrefix[numericLength] == '.'))
        {
            numericLength++;
        }

        var parsed = withoutPrefix[..numericLength]
            .Split('.', StringSplitOptions.RemoveEmptyEntries)
            .Select(part => int.TryParse(part, out var number) ? number : (int?)null)
            .Where(number => number.HasValue)
            .Select(number => number!.Value)
            .ToList();
        return parsed.Count == 0 ? null : new ReleaseVersion(parsed, trimmed);
    }

    public int CompareTo(ReleaseVersion? other)
    {
        if (other is null)
        {
            return 1;
        }

        var width = Math.Max(Components.Count, other.Components.Count);
        for (var index = 0; index < width; index++)
        {
            var left = index < Components.Count ? Components[index] : 0;
            var right = index < other.Components.Count ? other.Components[index] : 0;
            if (left != right)
            {
                return left.CompareTo(right);
            }
        }

        return 0;
    }

    public bool Equals(ReleaseVersion? other) => other is not null && CompareTo(other) == 0;

    public override bool Equals(object? obj) => Equals(obj as ReleaseVersion);

    public override int GetHashCode()
    {
        // Trailing zeros do not change ordering, so they must not change the hash either.
        var significant = Components.ToList();
        while (significant.Count > 0 && significant[^1] == 0)
        {
            significant.RemoveAt(significant.Count - 1);
        }

        var hash = new HashCode();
        foreach (var component in significant)
        {
            hash.Add(component);
        }

        return hash.ToHashCode();
    }

    public override string ToString() => Raw;

    public static bool operator <(ReleaseVersion left, ReleaseVersion right) => left.CompareTo(right) < 0;

    public static bool operator >(ReleaseVersion left, ReleaseVersion right) => left.CompareTo(right) > 0;
}

public enum ReleaseUpdateOutcomeKind
{
    UpToDate,
    UpdateAvailable,
    /// <summary>The check could not be completed. Never rendered as "up to date": not knowing and being current are different answers.</summary>
    Undetermined,
}

/// <summary>Mirrors macOS ReleaseUpdateOutcome, including which page (if any) the check should open.</summary>
public sealed record ReleaseUpdateOutcome(
    ReleaseUpdateOutcomeKind Kind,
    string? Current,
    string? Latest,
    string? ReleaseUrl,
    string? Reason)
{
    public static ReleaseUpdateOutcome UpToDate(string current) =>
        new(ReleaseUpdateOutcomeKind.UpToDate, current, null, null, null);

    public static ReleaseUpdateOutcome UpdateAvailable(string latest, string current, string releaseUrl) =>
        new(ReleaseUpdateOutcomeKind.UpdateAvailable, current, latest, releaseUrl, null);

    public static ReleaseUpdateOutcome Undetermined(string reason) =>
        new(ReleaseUpdateOutcomeKind.Undetermined, null, null, null, reason);

    /// <summary>
    /// The "never dead-ends" rule as a pure decision: up to date opens nothing, an available
    /// update opens that release, a failed check opens the releases page as a fallback.
    /// </summary>
    public string? UrlToOpen(string fallback) => Kind switch
    {
        ReleaseUpdateOutcomeKind.UpToDate => null,
        ReleaseUpdateOutcomeKind.UpdateAvailable => ReleaseUrl,
        _ => fallback,
    };

    /// <summary>Copy verbatim from ReleaseUpdateOutcome.userMessage in the macOS app.</summary>
    public string UserMessage => Kind switch
    {
        ReleaseUpdateOutcomeKind.UpToDate => $"BugNarrator {Current} is the latest release.",
        ReleaseUpdateOutcomeKind.UpdateAvailable => $"BugNarrator {Latest} is available — you are on {Current}. Opening the download page.",
        _ => $"BugNarrator could not check for updates: {Reason}",
    };
}

public sealed record LatestRelease(string Tag, string ReleaseUrl);

public interface ILatestReleaseFeed
{
    Task<LatestRelease> GetLatestReleaseAsync(CancellationToken cancellationToken = default);
}

/// <summary>
/// Reads the repository's public releases/latest. Unauthenticated and header-free beyond Accept
/// on purpose: no token, no install id, nothing that identifies who asked (macOS GitHubLatestReleaseFeed).
/// </summary>
public sealed class GitHubLatestReleaseFeed : ILatestReleaseFeed
{
    public const string Endpoint = "https://api.github.com/repos/ABD-Enterprises/bug-narrator/releases/latest";

    private readonly HttpClient httpClient;

    public GitHubLatestReleaseFeed(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
    }

    public async Task<LatestRelease> GetLatestReleaseAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, Endpoint);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        // GitHub rejects requests with no User-Agent; the product name carries nothing about the user.
        request.Headers.UserAgent.ParseAdd("BugNarrator");

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new ReleaseFeedException($"the releases feed answered {(int)response.StatusCode}");
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var payload = await JsonSerializer.DeserializeAsync<GitHubReleasePayload>(stream, cancellationToken: cancellationToken);
        if (payload is null || string.IsNullOrWhiteSpace(payload.TagName))
        {
            throw new ReleaseFeedException("the releases feed returned an unusable release");
        }

        if (!Uri.TryCreate(payload.HtmlUrl, UriKind.Absolute, out var releaseUrl)
            || (releaseUrl.Scheme != Uri.UriSchemeHttps && releaseUrl.Scheme != Uri.UriSchemeHttp))
        {
            throw new ReleaseFeedException("the releases feed returned an unusable link");
        }

        return new LatestRelease(payload.TagName, releaseUrl.AbsoluteUri);
    }

    private sealed record GitHubReleasePayload(
        [property: JsonPropertyName("tag_name")] string? TagName,
        [property: JsonPropertyName("html_url")] string? HtmlUrl);
}

public sealed class ReleaseFeedException(string message) : Exception(message);

/// <summary>The testable half of Check for Updates: everything except opening a browser (macOS ReleaseUpdateChecker).</summary>
public sealed class ReleaseUpdateChecker
{
    private readonly ILatestReleaseFeed feed;

    public ReleaseUpdateChecker(ILatestReleaseFeed? feed = null)
    {
        this.feed = feed ?? new GitHubLatestReleaseFeed();
    }

    public async Task<ReleaseUpdateOutcome> CheckAsync(string currentVersion, CancellationToken cancellationToken = default)
    {
        var current = ReleaseVersion.Parse(currentVersion);
        if (current is null)
        {
            return ReleaseUpdateOutcome.Undetermined("this build does not report a readable version");
        }

        LatestRelease latest;
        try
        {
            latest = await feed.GetLatestReleaseAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (ReleaseFeedException exception)
        {
            return ReleaseUpdateOutcome.Undetermined(exception.Message);
        }
        catch (HttpRequestException)
        {
            return ReleaseUpdateOutcome.Undetermined("the releases feed is unreachable (network failure)");
        }
        catch (Exception exception) when (exception is JsonException or TaskCanceledException)
        {
            return ReleaseUpdateOutcome.Undetermined(exception is JsonException
                ? "the releases feed returned an unreadable response"
                : "the releases feed timed out (network failure)");
        }

        var latestVersion = ReleaseVersion.Parse(latest.Tag);
        if (latestVersion is null)
        {
            return ReleaseUpdateOutcome.Undetermined($"the latest release tag '{latest.Tag}' is not a version");
        }

        return current < latestVersion
            ? ReleaseUpdateOutcome.UpdateAvailable(latestVersion.Raw, current.Raw, latest.ReleaseUrl)
            : ReleaseUpdateOutcome.UpToDate(current.Raw);
    }

    /// <summary>
    /// The version this build reports: the informational version without its build-metadata
    /// suffix (1.1.0+sha → 1.1.0), falling back to the assembly version.
    /// </summary>
    public static string CurrentVersion()
    {
        var assembly = System.Reflection.Assembly.GetEntryAssembly() ?? typeof(ReleaseUpdateChecker).Assembly;
        var informational = assembly
            .GetCustomAttributes(typeof(System.Reflection.AssemblyInformationalVersionAttribute), inherit: false)
            .OfType<System.Reflection.AssemblyInformationalVersionAttribute>()
            .FirstOrDefault()?.InformationalVersion;
        if (!string.IsNullOrWhiteSpace(informational))
        {
            var plus = informational.IndexOf('+');
            return plus >= 0 ? informational[..plus] : informational;
        }

        return assembly.GetName().Version?.ToString(3) ?? string.Empty;
    }
}
