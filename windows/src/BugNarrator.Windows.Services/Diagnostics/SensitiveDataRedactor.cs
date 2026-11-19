using System.Text.RegularExpressions;

namespace BugNarrator.Windows.Services.Diagnostics;

public static partial class SensitiveDataRedactor
{
    private const string RedactionToken = "[REDACTED]";

    [GeneratedRegex(@"(?im)(authorization\s*:\s*)([^\r\n]+)")]
    private static partial Regex AuthorizationHeaderRegex();

    [GeneratedRegex(@"(?i)\bBearer\s+[A-Za-z0-9._~+/-]+=*")]
    private static partial Regex BearerTokenRegex();

    // A Basic credential is the base64 of "user:secret", so the candidate has
    // to decode to something that contains a colon. The pattern only captures
    // the candidate; whether it is a credential is decided when the match is
    // replaced, so ordinary prose after the word "Basic" is left alone.
    [GeneratedRegex(@"(?i)\bBasic[ \t]+([A-Za-z0-9+/]+={0,2})(?![A-Za-z0-9+/=])")]
    private static partial Regex BasicTokenRegex();

    [GeneratedRegex(@"\bsk-[A-Za-z0-9_-]{6,}\b")]
    private static partial Regex OpenAiKeyRegex();

    [GeneratedRegex(@"\bgh[pousr]_[A-Za-z0-9_]{8,}\b")]
    private static partial Regex GitHubClassicTokenRegex();

    [GeneratedRegex(@"\bgithub_pat_[A-Za-z0-9_]{20,}\b")]
    private static partial Regex GitHubFineGrainedTokenRegex();

    // Atlassian API tokens carry a fixed ATATT3xFfGF0 prefix. Jira auth normally travels as
    // "Basic <base64>", which BasicTokenRegex covers, but a token pasted bare into a log line
    // (a settings dump, a copied error) must not survive into a debug bundle either.
    [GeneratedRegex(@"\bATATT3xFfGF0[A-Za-z0-9_\-=]{20,}\b")]
    private static partial Regex AtlassianApiTokenRegex();

    // Redacts the local-part of an email address (PII — e.g. the Jira account
    // email used for Basic auth) while keeping the domain for debuggability.
    [GeneratedRegex(@"(?i)\b[A-Za-z0-9._%+\-]+@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})\b")]
    private static partial Regex EmailRegex();

    public static string Redact(string? value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        var redactedValue = AuthorizationHeaderRegex().Replace(value, $"$1{RedactionToken}");
        redactedValue = BearerTokenRegex().Replace(redactedValue, $"Bearer {RedactionToken}");
        redactedValue = BasicTokenRegex().Replace(
            redactedValue,
            match => IsBasicCredential(match.Groups[1].Value) ? $"Basic {RedactionToken}" : match.Value);
        redactedValue = OpenAiKeyRegex().Replace(redactedValue, RedactionToken);
        redactedValue = GitHubClassicTokenRegex().Replace(redactedValue, RedactionToken);
        redactedValue = GitHubFineGrainedTokenRegex().Replace(redactedValue, RedactionToken);
        redactedValue = AtlassianApiTokenRegex().Replace(redactedValue, RedactionToken);
        redactedValue = EmailRegex().Replace(redactedValue, $"{RedactionToken}@$1");
        return redactedValue;
    }

    /// <summary>
    /// Whether the candidate decodes to a Basic credential, which is the base64
    /// of "user:secret" and therefore contains a colon. A candidate that does
    /// not decode, or that decodes to text without a colon, is ordinary prose
    /// and is not redacted.
    /// </summary>
    private static bool IsBasicCredential(string encoded)
    {
        var padded = encoded.PadRight(encoded.Length + ((4 - encoded.Length % 4) % 4), '=');
        Span<byte> decoded = new byte[(padded.Length / 4) * 3];
        if (!Convert.TryFromBase64String(padded, decoded, out var written))
        {
            return false;
        }

        return decoded[..written].IndexOf((byte)':') >= 0;
    }
}
