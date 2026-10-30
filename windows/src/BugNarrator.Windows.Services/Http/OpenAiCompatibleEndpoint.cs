using System.Net;
using System.Net.Sockets;

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

        var lowered = WithoutIPv6Brackets(host.ToLowerInvariant());

        // A host that carries a bracket in any other shape is not an address
        // the app checked.
        if (lowered is null)
        {
            return false;
        }

        if (IsReservedLocalhostName(lowered))
        {
            return true;
        }

        if (IsIPv6LocalEndpointHost(lowered))
        {
            return true;
        }

        if (TryParseDottedQuad(lowered, out var first, out var second, out var third, out var fourth))
        {
            // 0.0.0.0 is this machine. The rest of the 0.0.0.0/8 range is
            // not: 0.0.0.5 does not reach this machine, it is refused with
            // EHOSTUNREACH.
            if (first == 0 && second == 0 && third == 0 && fourth == 0)
            {
                return true;
            }

            return IsTrustedIPv4(first, second);
        }

        return false;
    }

    /// <summary>
    /// The host of <paramref name="url"/>, as it was written.
    /// </summary>
    /// <remarks>
    /// <see cref="Uri"/> rewrites a host that is a number written in another
    /// notation: <c>http://127.1/</c> and <c>http://0x7f000001/</c> both
    /// become <c>127.0.0.1</c>. The macOS port reads the host as it was
    /// written and refuses those spellings, so the Windows port has to read
    /// it the same way: the same URL cannot be trusted on one port and
    /// refused on the other.
    /// </remarks>
    public static string? HostAsWritten(string? url)
    {
        if (string.IsNullOrWhiteSpace(url))
        {
            return null;
        }

        var text = url.Trim();
        var schemeEnd = text.IndexOf("://", StringComparison.Ordinal);
        if (schemeEnd < 0)
        {
            return null;
        }

        var authority = text[(schemeEnd + 3)..];
        var end = authority.IndexOfAny(new[] { '/', '?', '#' });
        if (end >= 0)
        {
            authority = authority[..end];
        }

        // The user information comes before the host and is not part of it.
        var at = authority.LastIndexOf('@');
        if (at >= 0)
        {
            authority = authority[(at + 1)..];
        }

        if (authority.StartsWith('['))
        {
            // An IPv6 literal is written in brackets, and the port follows
            // the closing bracket.
            var close = authority.IndexOf(']');
            return close > 1 ? authority[..(close + 1)] : null;
        }

        // A name cannot contain a colon, so the last one separates the port.
        var colon = authority.LastIndexOf(':');
        if (colon >= 0)
        {
            authority = authority[..colon];
        }

        return authority.Length == 0 ? null : authority;
    }

    /// <summary>
    /// The host of <paramref name="url"/>, as it was written.
    /// </summary>
    public static string? HostAsWritten(Uri? url) =>
        url is null ? null : HostAsWritten(url.OriginalString);

    /// <summary>
    /// The host without the brackets an IPv6 literal is written in.
    /// </summary>
    /// <remarks>
    /// Only an IPv6 literal carries brackets. <c>[localhost]</c> is not one,
    /// and reading it as <c>localhost</c> would make the app trust a name it
    /// cannot check - the brackets are part of the host, not decoration.
    /// </remarks>
    private static string? WithoutIPv6Brackets(string host)
    {
        if (!host.Contains('[') && !host.Contains(']'))
        {
            return host;
        }

        // A bracket belongs to an IPv6 literal and to nothing else, and the
        // literal is the whole host: one pair of brackets around an address,
        // with nothing after it. `[[::1]]` is not a literal, and neither is
        // `[::1]:8080` - a port does not belong to the host. .NET's parser
        // accepts the brackets around a literal, so they have to come off
        // before the address is parsed.
        if (host.Length >= 2 && host[0] == '[' && host[^1] == ']')
        {
            var inner = host[1..^1];
            if (!inner.Contains('[') && !inner.Contains(']') && inner.Contains(':'))
            {
                return inner;
            }
        }

        return null;
    }

    /// <summary>
    /// The name <paramref name="host"/> refers to, with one trailing dot
    /// removed.
    /// </summary>
    /// <remarks>
    /// A trailing dot makes a name absolute rather than different: a resolver
    /// looks up the same name either way, so the two have to be classified the
    /// same way. It does not rescue an address literal - <c>127.0.0.1.</c> is
    /// not the address any more, it is a name the app cannot check.
    /// </remarks>
    private static string NameForm(string host)
    {
        return host.EndsWith(".", StringComparison.Ordinal) ? host[..^1] : host;
    }

    /// <summary>
    /// Whether <paramref name="host"/> is one of the names the standards
    /// reserve for the loopback: <c>localhost</c> itself, and a name under it.
    /// </summary>
    /// <remarks>
    /// Every label has to be there. A name that only looks like a reserved one
    /// - a leading dot, an empty label - is not one of them. A trailing dot
    /// is: it makes the name absolute rather than different, and a resolver
    /// answers a reserved name with the loopback address without ever putting
    /// the question to the network (RFC 6761).
    /// </remarks>
    private static bool IsReservedLocalhostName(string host)
    {
        var name = NameForm(host);
        if (name == "localhost")
        {
            return true;
        }

        if (!name.EndsWith(".localhost", StringComparison.Ordinal))
        {
            return false;
        }

        // The empty labels are the point: a name that starts or ends with a
        // dot leaves one behind, and ".localhost" is not the reserved name.
        var labels = name.Split('.');
        return labels.Length > 1 && labels.All(label => label.Length > 0);
    }

    /// <summary>
    /// Whether <paramref name="host"/> is written as an IPv6 literal that
    /// reaches this machine or the trusted local network.
    /// </summary>
    /// <remarks>
    /// The address is parsed, not compared as a string: <c>::1</c> can be
    /// written a dozen ways, and a comparison would refuse an endpoint the
    /// user can reach.
    /// </remarks>
    private static bool IsIPv6LocalEndpointHost(string host)
    {
        // A host that is not written as an IPv6 literal is not one.
        if (!host.Contains(':'))
        {
            return false;
        }

        // A zone id (`fe80::1%en0`) names the interface, not the address, so
        // it is removed before the address is parsed.
        var scope = host.IndexOf('%');
        var text = scope >= 0 ? host[..scope] : host;

        // An address that carries an IPv4 address in its last group has to
        // spell that address the way an address is written too. The mapped
        // form is another way to write the same address, and a leading zero
        // in it is the same ambiguity the canonical rule exists to remove.
        if (EmbeddedIPv4Text(text) is { } embedded && !TryParseDottedQuad(embedded, out _, out _))
        {
            return false;
        }

        if (!IPAddress.TryParse(text, out var address) ||
            address.AddressFamily != AddressFamily.InterNetworkV6)
        {
            return false;
        }

        var bytes = address.GetAddressBytes();

        // :: - the unspecified address, the IPv6 spelling of 0.0.0.0. A
        // connection to it reaches the loopback interface, the same way a
        // connection to 0.0.0.0 does, so the two spellings of "this machine"
        // have to be trusted together.
        if (bytes.All(value => value == 0))
        {
            return true;
        }

        // ::1 - the loopback.
        if (bytes.Take(15).All(value => value == 0) && bytes[15] == 1)
        {
            return true;
        }

        // fe80::/10 - the link-local range.
        if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80)
        {
            return true;
        }

        // ::ffff:a.b.c.d - an IPv4 address written as an IPv6 one.
        if (bytes[0..10].All(value => value == 0) && bytes[10] == 0xff && bytes[11] == 0xff)
        {
            // ::ffff:0.0.0.0 is 0.0.0.0 written as an IPv6 address, so it is
            // this machine the same way 0.0.0.0 is.
            if (bytes[12] == 0 && bytes[13] == 0 && bytes[14] == 0 && bytes[15] == 0)
            {
                return true;
            }

            return IsTrustedIPv4(bytes[12], bytes[13]);
        }

        return false;
    }

    /// <summary>
    /// The IPv4 address an IPv6 literal carries in its last group, if it has
    /// one.
    /// </summary>
    private static string? EmbeddedIPv4Text(string address)
    {
        if (!address.Contains('.'))
        {
            return null;
        }

        var tail = address.Split(':').LastOrDefault() ?? string.Empty;
        return tail.Contains('.') ? tail : null;
    }

    /// <summary>
    /// Whether an IPv4 address is one the app is willing to send a secret to
    /// over plaintext HTTP.
    /// </summary>
    private static bool IsTrustedIPv4(byte first, byte second)
    {
        return first switch
        {
            127 => true,                                // loopback 127.0.0.0/8
            10 => true,                                 // private 10.0.0.0/8
            192 when second == 168 => true,             // private 192.168.0.0/16
            169 when second == 254 => true,             // link-local 169.254.0.0/16
            172 when second >= 16 && second <= 31 => true, // private 172.16.0.0/12
            _ => false,
        };
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
        var lowered = WithoutIPv6Brackets(host.ToLowerInvariant());

        if (lowered is null || !TryParseDottedQuad(lowered, out var first, out var second, out var third, out var fourth))
        {
            return false;
        }

        // The unspecified, multicast and broadcast addresses are not a host on
        // the public internet: the 0.0.0.0/8 range means "this network" rather
        // than a destination (RFC 1122), and the other two are not addressed to
        // one host. Calling them remote would be a claim the app cannot make.
        if (first == 0)
        {
            return false;
        }

        if (first >= 224 && first <= 239)
        {
            return false;
        }

        if (first == 255 && second == 255 && third == 255 && fourth == 255)
        {
            return false;
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
        var lowered = WithoutIPv6Brackets(host.ToLowerInvariant());

        if (lowered is null)
        {
            return false;
        }

        // A trailing dot makes the name absolute rather than different: a
        // resolver answers the same name either way, so the two are the same
        // host and have to be classified the same way.
        var name = NameForm(lowered);

        if (name.Length == 0)
        {
            return false;
        }

        // An IPv4 literal in another notation - `134744072`, `0x7f000001` - is
        // an address, not a name anybody can claim for it.
        if (IsNumericAddressLiteral(name))
        {
            return false;
        }

        // `localhost` is reserved and always resolves to loopback.
        if (IsReservedLocalhostName(name))
        {
            return false;
        }

        if (name.EndsWith(".local", StringComparison.Ordinal))
        {
            return true;
        }

        return !name.Contains('.') && !name.Contains(':');
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
    /// its name is answered by the network rather than by the app. It names the
    /// fix, because the user is looking at a field they believe is correct.
    /// Mirrors SettingsStore.unqualifiedLocalHostPlaintextMessage in the macOS app.
    /// </summary>
    /// <remarks>
    /// The message does not claim that mDNS answers the name: a <c>.local</c>
    /// name is answered over mDNS, but a single-label name is answered through
    /// the resolver's search list, which is not always mDNS. The risk is the
    /// same either way - the app cannot check where the name points.
    /// </remarks>
    public static string UnqualifiedLocalHostPlaintextMessage(string host, string secret) =>
        $"{host} is not an address this app trusts for plaintext HTTP: a .local or single-word host "
        + "name is answered by the network rather than by the app, so it can point anywhere and the "
        + "traffic could be intercepted. Use that host's IP address (for example 192.168.1.20), "
        + $"or https://. Over plaintext HTTP your {secret} would cross the network unencrypted.";

    /// <summary>
    /// The refusal to use a plaintext HTTP endpoint for a host the app cannot
    /// check, in one sentence for one host.
    /// </summary>
    /// <remarks>
    /// Every surface that refuses such a host builds its message here, so the
    /// warning next to the setting and the refusal that blocks the request
    /// cannot describe one host two different ways. Mirrors
    /// <c>SettingsStore.plaintextTransportRefusal</c> in the macOS app.
    /// </remarks>
    public static string PlaintextTransportRefusal(string host, string subject, string secret, string localNoun)
    {
        if (IsUnqualifiedLocalName(host))
        {
            return UnqualifiedLocalHostPlaintextMessage(host, secret);
        }

        if (IsPublicAddress(host))
        {
            return $"{subject} uses plaintext HTTP to a remote host ({host}). "
                + $"Your {secret} would be sent unencrypted. "
                + $"Use https://, or configure a trusted local {localNoun}.";
        }

        return $"{subject} uses plaintext HTTP to a host this app cannot use as a local "
            + $"address ({host}). Your {secret} would be sent unencrypted. "
            + "Use https://, or point this at an address the app can check.";
    }

    /// <summary>
    /// A user-facing warning when the configured base URL would transmit the API
    /// key and transcript content to a non-local host over plaintext HTTP. Remote
    /// HTTPS and local HTTP (loopback/private/link-local) return null so enterprise-proxy
    /// and local-provider workflows are not nagged. Mirrors the macOS app (#472).
    /// </summary>
    public static string? PlaintextRemoteWarning(string? configuredBaseUrl)
    {
        var host = PlaintextHttpHost(configuredBaseUrl);
        if (host is null)
        {
            return null;
        }

        return PlaintextTransportRefusal(
            host, "This endpoint", "API key and transcript text", "endpoint");
    }

    /// <summary>
    /// The host of <paramref name="configuredBaseUrl"/> when it is a plaintext
    /// HTTP URL the app cannot check as a local address, and null when there
    /// is nothing to refuse.
    /// </summary>
    /// <remarks>
    /// The host is read as it was written: .NET rewrites a number written in
    /// another notation into the address it stands for, and the macOS port
    /// refuses those spellings, so the same URL cannot be trusted on one port
    /// and refused on the other.
    /// <para>
    /// A URL that .NET cannot parse at all is still judged. <c>http://[localhost]
    /// </c> is one, because a bracket belongs to an IPv6 literal and to nothing
    /// else - and a secret must not go out to a host the app cannot check just
    /// because the URL is malformed.
    /// </para>
    /// </remarks>
    public static string? PlaintextHttpHost(string? configuredBaseUrl)
    {
        if (string.IsNullOrWhiteSpace(configuredBaseUrl))
        {
            return null;
        }

        var text = configuredBaseUrl.Trim();

        if (Uri.TryCreate(text, UriKind.Absolute, out var parsed))
        {
            if (!string.Equals(parsed.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            // A URL whose text does not yield a host is judged by the host
            // .NET parsed, so the refusal is never silently dropped.
            var host = HostAsWritten(text) ?? parsed.Host;
            return host is null || IsLocalEndpointHost(host) ? null : host;
        }

        // The URL does not parse. The scheme and the host can still be read
        // out of the text.
        var schemeEnd = text.IndexOf("://", StringComparison.Ordinal);
        if (schemeEnd <= 0
            || !string.Equals(text[..schemeEnd], Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var hostAsWritten = HostAsWritten(text);
        return hostAsWritten is null || IsLocalEndpointHost(hostAsWritten) ? null : hostAsWritten;
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
    /// Whether <paramref name="host"/> is a dotted-quad IPv4 literal written the
    /// way an address is written, and if so its first two octets.
    /// </summary>
    /// <remarks>
    /// Only decimal digits count: <c>byte.TryParse</c> would also accept a sign
    /// or surrounding whitespace, which the macOS parser rejects. A leading
    /// zero is rejected too, because it is another spelling of the same octet
    /// rather than the octet itself: .NET reads <c>010.0.0.1</c> as eight, so
    /// the app and the network would disagree about what the host is.
    /// </remarks>
    private static bool TryParseDottedQuad(string host, out byte first, out byte second)
    {
        return TryParseDottedQuad(host, out first, out second, out _, out _);
    }

    /// <summary>
    /// The four octets of <paramref name="host"/>, when it is an IPv4 literal
    /// written the way an address is written.
    /// </summary>
    /// <remarks>
    /// The spelling has to be canonical, because the app and the network have
    /// to read the host the same way. A leading zero (<c>010.0.0.1</c>) is a
    /// different octet to a resolver that reads it as octal - eight, not ten -
    /// and a trailing or leading dot (<c>127.0.0.1.</c>) turns the host into an
    /// absolute DNS name that a resolver anywhere on the network can answer.
    /// </remarks>
    private static bool TryParseDottedQuad(
        string host,
        out byte first,
        out byte second,
        out byte third,
        out byte fourth)
    {
        first = 0;
        second = 0;
        third = 0;
        fourth = 0;

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

            if (part.Length > 1 && part[0] == '0')
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
        third = octets[2];
        fourth = octets[3];
        return true;
    }

    private static bool IsHexDigit(char value) =>
        value is >= '0' and <= '9' or >= 'a' and <= 'f' or >= 'A' and <= 'F';
}
