using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace BugNarrator.Core.Models;

/// <summary>
/// Derives the stable duplicate-detection hint for an extracted issue.
///
/// This mirrors the macOS <c>ExtractedIssue.makeDeduplicationHint</c>
/// (Sources/BugNarrator/Models/IssueCore.swift) byte for byte: the same normalization and the same
/// FNV-1a 64-bit hash, so the same issue produces the same hint on both platforms. Diverging here
/// would silently break cross-platform duplicate recognition, which is the whole point of the field.
/// </summary>
public static class IssueDeduplication
{
    private const string EmptyHint = "issue-0000000000000000";

    private static readonly Regex WhitespaceRun = new(@"\s+", RegexOptions.Compiled);

    public static string MakeHint(string title, string summary, string evidenceExcerpt)
    {
        var normalized = Normalize(string.Join("\n", title, summary, evidenceExcerpt));
        if (normalized.Length == 0)
        {
            return EmptyHint;
        }

        // FNV-1a, 64-bit. unchecked so the multiply wraps like Swift's &*=.
        var hash = 14695981039346656037UL;
        const ulong Prime = 1099511628211UL;

        foreach (var b in Encoding.UTF8.GetBytes(normalized))
        {
            hash ^= b;
            unchecked
            {
                hash *= Prime;
            }
        }

        return $"issue-{hash:x16}";
    }

    /// <summary>
    /// Case- and diacritic-insensitive folding with runs of whitespace collapsed, matching the
    /// macOS `.folding(options: [.caseInsensitive, .diacriticInsensitive])` pipeline.
    /// </summary>
    private static string Normalize(string value)
    {
        var decomposed = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);

        foreach (var character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character) != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(character);
            }
        }

        var folded = builder.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();

        return WhitespaceRun.Replace(folded, " ").Trim();
    }
}
