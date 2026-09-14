using System.Net;
using System.Text.Json;

namespace BugNarrator.Windows.Services.LocalTranscription;

public interface ILocalServerHealthProbe
{
    /// <summary>True only when GET {baseUrl}/health answers 200 with JSON status == "ok" within the timeout.</summary>
    Task<bool> IsReachableAsync(string baseUrl, CancellationToken cancellationToken = default);
}

/// <summary>
/// The readiness signal for the Local (Parakeet) provider, mirroring macOS
/// SettingsStore.isHealthyLocalProvider / refreshLocalProviderReachabilityIfNeeded: 2 s timeout, no
/// caching, anything but 200 + <c>{"status":"ok"}</c> is unreachable. Nothing else in the app
/// decides Parakeet readiness; the recording preflight and Check Server both ask this.
/// </summary>
public sealed class LocalServerHealthProbe : ILocalServerHealthProbe
{
    public static readonly TimeSpan Timeout = TimeSpan.FromSeconds(2);

    /// <summary>Poll cadence while the provider is Parakeet, as macOS re-schedules every 2 s.</summary>
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(2);

    /// <summary>Shown when a recording is refused because the server is not answering (product-spec "fail before transcription").</summary>
    public const string UnreachableMessage =
        "The local Parakeet transcription server is not responding on port 8422. Start it in Settings before recording.";

    private readonly HttpClient httpClient;

    public LocalServerHealthProbe(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient { Timeout = Timeout };
    }

    public static bool IsHealthy(HttpStatusCode status, string? body)
    {
        if (status != HttpStatusCode.OK || string.IsNullOrWhiteSpace(body))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(body);
            return document.RootElement.ValueKind == JsonValueKind.Object
                && document.RootElement.TryGetProperty("status", out var value)
                && value.ValueKind == JsonValueKind.String
                && value.GetString() == "ok";
        }
        catch (JsonException)
        {
            return false;
        }
    }

    public async Task<bool> IsReachableAsync(string baseUrl, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(baseUrl.TrimEnd('/') + "/health", UriKind.Absolute, out var url))
        {
            return false;
        }

        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(Timeout);
            using var request = new HttpRequestMessage(HttpMethod.Get, url);
            request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue { NoCache = true };
            using var response = await httpClient.SendAsync(request, timeout.Token);
            var body = await response.Content.ReadAsStringAsync(timeout.Token);
            return IsHealthy(response.StatusCode, body);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception)
        {
            // Timeout, refused connection, malformed response: all "not reachable", never an error.
            return false;
        }
    }
}
