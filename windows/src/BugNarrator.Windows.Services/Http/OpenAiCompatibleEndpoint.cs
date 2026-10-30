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
    /// Whether <paramref name="host"/> denotes a loopback / private / link-local
    /// endpoint, for which plaintext HTTP is acceptable because the traffic
    /// stays on the machine or the trusted local network.
    ///
    /// A <c>.local</c> name and a single-label name such as <c>lmstudio</c> are
    /// deliberately not trusted. Both are resolved over mDNS, which any device on
    /// the local network can answer, so a name that looks local can point
    /// anywhere. A local server is addressed by its IP address instead.
    /// Mirrors SettingsStore.isLocalEndpointHost in the macOS app (#1268).
    /// </summary>
    public static bool IsLocalEndpointHost(string host)
    {
        if (string.IsNullOrWhiteSpace(host))
        {
            return false;
        }

        var lowered = host.ToLowerInvariant().Trim('[', ']');

        // `localhost` is reserved and always resolves to loopback.
        if (lowered == "localhost" || lowered.EndsWith(".localhost", StringComparison.Ordinal))
        {
            return true;
        }

        // IPv6 loopback / link-local.
        if (lowered == "::1" || lowered.StartsWith("fe80:", StringComparison.Ordinal))
        {
            return true;
        }

        if (TryParseDottedQuad(lowered, out var first, out var second))
        {
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
    /// Whether <paramref name="host"/> is an address the app parsed and found to
    /// be somewhere else - a public address, written the way an address is
    /// written.
    /// </summary>
    /// <remarks>
    /// A host in another notation (<c>134744072</c>, <c>127.1</c>) is not
    /// parseable, so it is neither a local nor a public address as far as the app
    /// is concerned: the app cannot say where it points.
    /// Mirrors SettingsStore.isPublicAddress in the macOS app.
    /// </remarks>
    public static bool IsPublicAddress(string host)
    {
        var lowered = host.ToLowerInvariant().Trim('[', ']');

        var parts = lowered.Split('.');
        if (parts.Length != 4)
        {
            return false;
        }

        foreach (var part in parts)
        {
            if (part.Length == 0 || !part.All(char.IsAsciiDigit) || !byte.TryParse(part, out _))
            {
                return false;
            }
        }

        return !IsLocalEndpointHost(host);
    }

    /// <summary>
    /// Whether <paramref name="host"/> is a name that resolves over mDNS rather
    /// than an address the app can check: a <c>.local</c> name, or a single-label
    /// name such as <c>lmstudio</c>. Any device on the local network can answer
    /// for such a name, so it is not a trusted endpoint even though it looks
    /// local. Mirrors SettingsStore.isUnqualifiedLocalName in the macOS app.
    /// </summary>
    public static bool IsUnqualifiedLocalName(string host)
    {
        var lowered = host.ToLowerInvariant().Trim('[', ']');

        if (lowered.Length == 0)
        {
            return false;
        }

        // An IPv4 literal in another notation - `134744072`, `0x7f000001` - is
        // an address, not a name anybody can claim for it.
        if (IsNumericAddressLiteral(lowered))
        {
            return false;
        }

        // `localhost` is reserved and always resolves to loopback.
        if (lowered == "localhost" || lowered.EndsWith(".localhost", StringComparison.Ordinal))
        {
            return false;
        }

        if (lowered.EndsWith(".local", StringComparison.Ordinal))
        {
            return true;
        }

        return !lowered.Contains('.') && !lowered.Contains(':');
    }

    /// <summary>
    /// Whether <paramref name="host"/> is a number written in a notation other
    /// than the dotted quad: decimal (<c>134744072</c>) or hexadecimal
    /// (<c>0x7f000001</c>). Mirrors SettingsStore.isNumericAddressLiteral in
    /// the macOS app.
    /// </summary>
    public static bool IsNumericAddressLiteral(string host)
    {
        if (host.Length == 0)
        {
            return false;
        }

        if (host.All(char.IsAsciiDigit))
        {
            return true;
        }

        if (!host.StartsWith("0x", StringComparison.Ordinal) && !host.StartsWith("0X", StringComparison.Ordinal))
        {
            return false;
        }

        var digits = host[2..];
        return digits.Length > 0 && digits.All(IsHexDigit);
    }

    /// <summary>
    /// The message for an endpoint that is refused over plaintext HTTP because
    /// its name can be claimed by any device on the local network. It names the
    /// fix, because the user is looking at a field they believe is correct.
    /// Mirrors SettingsStore.unqualifiedLocalHostPlaintextMessage in the macOS app.
    /// </summary>
    public static string UnqualifiedLocalHostPlaintextMessage(string host, string secret) =>
        $"{host} is not an address this app trusts for plaintext HTTP: a .local or single-word host "
        + "name can be claimed by any device on the local network, so the traffic could be "
        + "intercepted. Use the machine's IP address (for example 192.168.1.20), or https://. "
        + $"Over plaintext HTTP your {secret} would cross the network unencrypted.";

    /// <summary>
    /// A user-facing warning when the configured base URL would transmit the API
    /// key and transcript content to a non-local host over plaintext HTTP. Remote
    /// HTTPS and local HTTP (loopback/private/link-local) return null so enterprise-proxy
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

        if (IsUnqualifiedLocalName(parsed.Host))
        {
            return UnqualifiedLocalHostPlaintextMessage(parsed.Host, "API key and transcript text");
        }

        if (IsPublicAddress(parsed.Host))
        {
            return "This endpoint uses plaintext HTTP to a remote host "
                + $"({parsed.Host}). Your API key and transcript text would be sent "
                + "unencrypted. Use https:// unless this is a trusted local endpoint.";
        }

        return "This endpoint uses plaintext HTTP to a host this app cannot check as a local "
            + $"address ({parsed.Host}). Your API key and transcript text would be sent "
            + "unencrypted. Use https://, or point this at an address the app can check.";
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

    /// <summary>
    /// Whether <paramref name="host"/> is a dotted-quad IPv4 literal, and if so
    /// its first two octets. Only decimal digits count: <c>byte.TryParse</c>
    /// would also accept a sign or surrounding whitespace, which the macOS
    /// parser rejects.
    /// </summary>
    private static bool TryParseDottedQuad(string host, out byte first, out byte second)
    {
        first = 0;
        second = 0;

        var parts = host.Split('.');
        if (parts.Length != 4)
        {
            return false;
        }

        var octets = new byte[4];
        for (var index = 0; index < parts.Length; index++)
        {
            var part = parts[index];
            if (part.Length == 0 || !part.All(char.IsAsciiDigit))
            {
                return false;
            }

            if (!byte.TryParse(part, out octets[index]))
            {
                return false;
            }
        }

        first = octets[0];
        second = octets[1];
        return true;
    }

    private static bool IsHexDigit(char value) =>
        value is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F';
}
