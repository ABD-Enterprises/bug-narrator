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
    // to decode to text with a colon in it. The pattern only captures the
    // candidate; whether it is a credential is decided when the match is
    // replaced, so ordinary prose after the word "Basic" is left alone.
    //
    // The candidate is the whole run of base64-shaped characters, with no
    // trailing boundary: a credential is often followed by more of them, and a
    // boundary that rejected those would let the credential through.
    [GeneratedRegex(@"(?i)\bBasic\s+([A-Za-z0-9+/=]{8,})")]
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
    /// Whether the candidate holds a Basic credential, which is the base64 of
    /// "user:secret": text with a colon in it and something on both sides of
    /// the colon. A candidate that does not decode to that is ordinary prose
    /// and is not redacted.
    /// </summary>
    private static bool IsBasicCredential(string candidate)
    {
        // A run this long is not a word. It is data, and redacting it is the
        // safe answer, so it is not searched through.
        if (candidate.Length > MaximumCandidateLength)
        {
            return true;
        }

        // The credential may sit at the start of the run or at the end of it.
        // The run is everything that follows the word "Basic", and the
        // characters around the credential are often more of the same
        // alphabet, so the credential is found by looking at the run from both
        // ends.
        for (var length = candidate.Length; length >= MinimumCredentialLength; length--)
        {
            if (DecodesToCredential(candidate[..length]))
            {
                return true;
            }
        }

        for (var start = 1; start <= candidate.Length - MinimumCredentialLength; start++)
        {
            if (DecodesToCredential(candidate[start..]))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>The shortest candidate that can hold a credential.</summary>
    private const int MinimumCredentialLength = 8;

    /// <summary>
    /// The longest candidate that is searched through for a credential. A
    /// credential is a user name and a password, which are far shorter than
    /// this, so a longer run is data rather than a credential.
    /// </summary>
    private const int MaximumCandidateLength = 512;

    private static bool DecodesToCredential(string encoded)
    {
        var padded = encoded.PadRight(encoded.Length + ((4 - encoded.Length % 4) % 4), '=');
        Span<byte> decoded = new byte[(padded.Length / 4) * 3];
        if (!Convert.TryFromBase64String(padded, decoded, out var written))
        {
            return false;
        }

        var text = decoded[..written];
        var colon = text.IndexOf((byte)':');
        if (colon <= 0 || colon == text.Length - 1)
        {
            return false;
        }

        // A credential is text. A control character means the decode did not
        // land on text, which is what tells a credential apart from a word:
        // an ordinary word decodes to bytes that are not text. A byte above
        // the printable ASCII range is text in another encoding, and a
        // credential may well use one.
        foreach (var value in text)
        {
            if (value < 0x20 || value == 0x7f)
            {
                return false;
            }
        }

        return true;
    }
}
