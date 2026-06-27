namespace BugNarrator.Windows.Services.Http;

public static class OpenAiCompatibleEndpoint
{
    private static readonly Uri DefaultBaseUri = new("https://api.openai.com/v1/");

    public static Uri Build(string? configuredBaseUrl, string relativePath)
    {
        if (string.IsNullOrWhiteSpace(relativePath))
        {
            throw new ArgumentException("Endpoint path is required.", nameof(relativePath));
        }

        var baseUri = NormalizeBaseUri(configuredBaseUrl);
        return new Uri(baseUri, relativePath.TrimStart('/'));
    }

    public static string NormalizeForStorage(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return string.Empty;
        }

        return NormalizeBaseUri(configuredBaseUrl).ToString().TrimEnd('/');
    }

    /// <summary>
    /// Whether <paramref name="host"/> denotes a loopback / private / link-local /
    /// .local endpoint, for which plaintext HTTP is acceptable because the traffic
    /// stays on the machine or the trusted local network.
    /// </summary>
    public static bool IsLocalEndpointHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        var lowered = host.Trim().Trim('[', ']').ToLowerInvariant();

        if (lowered == "localhost" || lowered.EndsWith(".localhost", StringComparison.Ordinal))
        {
            return true;
        }

        if (lowered.EndsWith(".local", StringComparison.Ordinal))
        {
            return true;
        }

        // Single-label hostnames (e.g. "lmstudio") never resolve on public DNS.
        if (!lowered.Contains('.') && !lowered.Contains(':'))
        {
            return true;
        }

        // IPv6 loopback / link-local.
        if (lowered == "::1" || lowered.StartsWith("fe80:", StringComparison.Ordinal))
        {
            return true;
        }

        var parts = lowered.Split('.');
        if (parts.Length == 4 && parts.All(part => byte.TryParse(part, out _)))
        {
            var first = byte.Parse(parts[0]);
            var second = byte.Parse(parts[1]);
            return first switch
            {
                127 => true,                       // loopback 127.0.0.0/8
                10 => true,                        // private 10.0.0.0/8
                192 when second == 168 => true,    // private 192.168.0.0/16
                169 when second == 254 => true,    // link-local 169.254.0.0/16
                172 when second >= 16 && second <= 31 => true, // private 172.16.0.0/12
                _ => false,
            };
        }

        return false;
    }

    /// <summary>
    /// A user-facing warning when the configured base URL would transmit the API
    /// key and transcript content to a non-local host over plaintext HTTP. Remote
    /// HTTPS and local HTTP (loopback/private/.local) return null so enterprise-proxy
    /// and local-provider workflows are not nagged. Mirrors the macOS app (#472).
    /// </summary>
    public static string? PlaintextRemoteWarning(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return null;
        }

        if (!Uri.TryCreate(configuredBaseUrl.Trim(), UriKind.Absolute, out var parsed))
        {
            return null;
        }

        if (!string.Equals(parsed.Scheme, "http", StringComparison.OrdinalIgnoreCase)
            || IsLocalEndpointHost(parsed.Host))
        {
            return null;
        }

        return $"This endpoint uses plaintext HTTP to a remote host ({parsed.Host}). "
            + "Your API key and transcript text would be sent unencrypted. Use "
            + "https:// unless this is a trusted local endpoint.";
    }

    private static Uri NormalizeBaseUri(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return DefaultBaseUri;
        }

        if (!Uri.TryCreate(configuredBaseUrl.Trim(), UriKind.Absolute, out var parsed)
            || parsed.Scheme is not ("http" or "https"))
        {
            throw new InvalidOperationException("AI provider base URL must be an absolute HTTP or HTTPS URL.");
        }

        var builder = new UriBuilder(parsed);
        var path = builder.Path.Trim('/');
        builder.Path = string.IsNullOrWhiteSpace(path)
            ? "v1/"
            : $"{path}/";
        builder.Query = string.Empty;
        builder.Fragment = string.Empty;
        return builder.Uri;
    }
}
