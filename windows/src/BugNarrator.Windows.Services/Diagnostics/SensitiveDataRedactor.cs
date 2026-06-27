using System.Text.RegularExpressions;

namespace BugNarrator.Windows.Services.Diagnostics;

internal static partial class SensitiveDataRedactor
{
    private const string RedactionToken = "[REDACTED]";

    [GeneratedRegex(@"(?im)(authorization\s*:\s*)([^\r\n]+)")]
    private static partial Regex AuthorizationHeaderRegex();

    [GeneratedRegex(@"(?i)\bBearer\s+[A-Za-z0-9._\-+/=]+\b")]
    private static partial Regex BearerTokenRegex();

    [GeneratedRegex(@"(?i)\bBasic\s+[A-Za-z0-9+/=]{8,}\b")]
    private static partial Regex BasicTokenRegex();

    [GeneratedRegex(@"\bsk-[A-Za-z0-9_-]{6,}\b")]
    private static partial Regex OpenAiKeyRegex();

    [GeneratedRegex(@"\bgh[pousr]_[A-Za-z0-9_]{8,}\b")]
    private static partial Regex GitHubClassicTokenRegex();

    [GeneratedRegex(@"\bgithub_pat_[A-Za-z0-9_]{20,}\b")]
    private static partial Regex GitHubFineGrainedTokenRegex();

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
        redactedValue = BasicTokenRegex().Replace(redactedValue, $"Basic {RedactionToken}");
        redactedValue = OpenAiKeyRegex().Replace(redactedValue, RedactionToken);
        redactedValue = GitHubClassicTokenRegex().Replace(redactedValue, RedactionToken);
        redactedValue = GitHubFineGrainedTokenRegex().Replace(redactedValue, RedactionToken);
        redactedValue = EmailRegex().Replace(redactedValue, $"{RedactionToken}@$1");
        return redactedValue;
    }
}
