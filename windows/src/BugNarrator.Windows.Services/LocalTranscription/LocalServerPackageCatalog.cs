using BugNarrator.Windows.Services.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace BugNarrator.Windows.Services.LocalTranscription;

public sealed record LocalServerAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("size")] long Size,
    [property: JsonPropertyName("browser_download_url")] string BrowserDownloadUrl);

public sealed record LocalServerRelease(
    [property: JsonPropertyName("draft")] bool Draft,
    [property: JsonPropertyName("prerelease")] bool Prerelease,
    [property: JsonPropertyName("assets")] IReadOnlyList<LocalServerAsset> Assets);

/// <summary>The signed server zip and its checksum manifest, as macOS LocalTranscriptionManager.Package.</summary>
public sealed record LocalServerPackage(LocalServerAsset Image, LocalServerAsset Checksum);

/// <summary>
/// Finds the signed Windows server asset on the project's GitHub Releases, mirroring the macOS
/// selectPackage / trustedAssetURL rules: first non-draft, non-prerelease release carrying both the
/// zip and its .sha256, size-bounded, and only from the project's own releases download path.
/// App and server releases have independent cadences, so the search is bounded to 20 pages of 30.
/// </summary>
public sealed class LocalServerPackageCatalog
{
    public const string AssetName = "bugnarrator-transcription-windows-x64.zip";
    public const string ChecksumAssetName = AssetName + ".sha256";
    public const string ReleasesEndpoint = "https://api.github.com/repos/SureForgeTech/sureforge-capture/releases";
    public const string TrustedDownloadPrefix = "/SureForgeTech/sureforge-capture/releases/download/";
    public const int PageSize = 30;
    public const int MaxPages = 20;
    public const long MaxImageBytes = 1_000_000_000;
    public const long MaxChecksumBytes = 4096;

    private readonly HttpClient httpClient;
    private readonly Architecture architecture;

    public LocalServerPackageCatalog(HttpClient? httpClient = null, Architecture? architecture = null)
    {
        this.httpClient = httpClient ?? new HttpClient { Timeout = TimeSpan.FromSeconds(30) };
        this.architecture = architecture ?? RuntimeInformation.ProcessArchitecture;
    }

    public static string? AssetNameForArchitecture(Architecture architecture) => architecture switch
    {
        Architecture.X64 => AssetName,
        Architecture.Arm64 => "bugnarrator-transcription-windows-arm64.zip",
        _ => null,
    };

    public static LocalServerPackage? SelectPackage(IReadOnlyList<LocalServerRelease> releases, Architecture? architecture = null)
    {
        var assetName = AssetNameForArchitecture(architecture ?? RuntimeInformation.ProcessArchitecture);
        if (assetName is null) return null;
        foreach (var release in releases)
        {
            if (release.Draft || release.Prerelease || release.Assets is null)
            {
                continue;
            }

            var image = release.Assets.FirstOrDefault(asset => asset.Name == assetName);
            var checksum = release.Assets.FirstOrDefault(asset => asset.Name == assetName + ".sha256");
            if (image is null || checksum is null)
            {
                continue;
            }

            if (image.Size > 0 && image.Size < MaxImageBytes
                && checksum.Size > 0 && checksum.Size < MaxChecksumBytes
                && TrustedAssetUrl(image.BrowserDownloadUrl) && TrustedAssetUrl(checksum.BrowserDownloadUrl))
            {
                return new LocalServerPackage(image, checksum);
            }
        }

        return null;
    }

    public static bool TrustedAssetUrl(string? value)
    {
        return Uri.TryCreate(value, UriKind.Absolute, out var url)
            && url.Scheme == Uri.UriSchemeHttps
            && url.Host == "github.com"
            && url.IsDefaultPort
            && string.IsNullOrEmpty(url.UserInfo)
            && string.IsNullOrEmpty(url.Query) && string.IsNullOrEmpty(url.Fragment)
            && url.AbsolutePath.StartsWith(TrustedDownloadPrefix, StringComparison.Ordinal);
    }

    /// <summary>
    /// Returns the package, or a user-facing message when none is found (null package). Mirrors
    /// the macOS discover() messages.
    /// </summary>
    public async Task<(LocalServerPackage? Package, string Message)> DiscoverAsync(CancellationToken cancellationToken = default)
    {
        if (AssetNameForArchitecture(architecture) is null)
        {
            return (null, "No local server package supports this process architecture. Choose another transcription provider.");
        }
        try
        {
            for (var page = 1; page <= MaxPages; page++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                using var request = new HttpRequestMessage(HttpMethod.Get, $"{ReleasesEndpoint}?per_page={PageSize}&page={page}");
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
                request.Headers.UserAgent.ParseAdd("BugNarrator");
                using var response = await httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                if (!response.IsSuccessStatusCode)
                {
                    throw new LocalServerFailure("The download server returned an unsuccessful response");
                }

                var body = await ResponseBodyReader.ReadAsync(response, cancellationToken);
                var releases = JsonSerializer.Deserialize<List<LocalServerRelease>>(body)
                    ?? [];
                if (SelectPackage(releases, architecture) is { } found)
                {
                    return (found, string.Empty);
                }

                if (releases.Count < PageSize)
                {
                    return (null, "No compatible signed server release was found. Try again later or choose OpenAI.");
                }
            }

            return (null, "Server release search reached its limit. Check the project releases or choose OpenAI.");
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            return (null, $"Could not check server releases: {exception.Message}. Try again.");
        }
    }
}

public sealed class LocalServerFailure(string message) : Exception(message);
