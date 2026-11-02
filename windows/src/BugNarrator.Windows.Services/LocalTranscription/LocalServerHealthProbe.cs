using System.Linq;
using System.Net;
using System.Security.Cryptography;
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

    /// <summary>
    /// Where the token file lives. The directory the app installs into, unless
    /// a caller says otherwise.
    /// </summary>
    private readonly string installDirectory;

    public LocalServerHealthProbe(HttpClient? httpClient = null, string? installDirectory = null)
    {
        this.httpClient = httpClient ?? new HttpClient { Timeout = Timeout };
        this.installDirectory = installDirectory ?? LocalServerPaths.DefaultInstallDirectory;
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
                && value.GetString() == "ok"
                // `model_loaded` has to be true as well: a stub that answers
                // {"status":"ok"} is not a Parakeet server, and the health probe
                // is what decides whether the app hands it the user's audio
                // (#1270).
                && document.RootElement.TryGetProperty("model_loaded", out var loaded)
                && loaded.ValueKind == JsonValueKind.True;
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
            // The peer has to prove that it is the server before the app hands
            // it anything. A listener that answers on the port is not the
            // server, and the app must not learn its token from the first
            // request it sends (#1270). So the challenge carries a fresh
            // nonce and no token: the server answers with an HMAC of the
            // nonce that only a peer that knows the token can produce, and the
            // app sends the token on later requests only once that proof
            // checks out.
            var nonce = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
            request.Headers.TryAddWithoutValidation(LocalServerTokenStore.ChallengeHeader, nonce);
            var token = LocalServerTokenStore.Token(installDirectory);
            var expectedProof = string.IsNullOrWhiteSpace(token)
                ? null
                : LocalServerTokenStore.Proof(nonce, token);
            using var response = await httpClient.SendAsync(request, timeout.Token);
            var body = await response.Content.ReadAsStringAsync(timeout.Token);
            if (expectedProof is null)
            {
                return false;
            }

            // The peer has to prove that it knows the token. A listener that
            // answers the health check with the right body is still not the
            // server, and the app must not upload the user's audio to it.
            var proof = response.Headers.TryGetValues(LocalServerTokenStore.ProofHeader, out var values)
                ? values.FirstOrDefault()
                : null;
            if (!string.Equals(proof, expectedProof, StringComparison.Ordinal))
            {
                return false;
            }

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
