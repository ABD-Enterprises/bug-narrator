using System.Text.RegularExpressions;

namespace BugNarrator.Core.Export;

/// <summary>
/// Neutralizes model- and transcript-derived text before it is placed in a GitHub issue body.
/// A line-for-line port of macOS <c>GitHubExportProvider.neutralizingUntrustedMarkdown</c>
/// (#1118); lives in Core so its tests run on every OS (#1200).
/// </summary>
public static partial class UntrustedMarkdown
{
    private const string ZeroWidthSpace = "​";

    // Block-level syntax is decided by the first NON-SPACE character (CommonMark allows up to
    // three spaces of indent). ":" starts a table delimiter row (":--|:--") with no leading pipe.
    private const string BlockStarters = "-*+|=`~_:";

    public static string Neutralize(string? text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text ?? string.Empty;
        }

        // GitHub treats a lone CR as a line break; splitting on "\n" alone would leave every
        // line-start escape below unapplied after one.
        var lines = text.Replace("\r\n", "\n").Replace("\r", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            var escaped = lines[i]
                // First, so an attacker's own backslash cannot pair with one we add below
                // ("\\[" is a literal backslash followed by a LIVE "[").
                .Replace("\\", "\\\\")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                // A zero-width space after @/# breaks GitHub's mention and issue autolinks (and
                // defeats `# heading` injection) while leaving the text visually identical.
                .Replace("@", "@" + ZeroWidthSpace)
                .Replace("#", "#" + ZeroWidthSpace)
                // An escaped "[" cannot open a link or image label, so [text](url), ![alt](url)
                // and [ref]: url all render literally. Bare URLs are left alone: GitHub
                // autolinks them and the target is what the reader sees.
                .Replace("[", "\\[");
            // "GH-123" is an issue reference GitHub links just like "#123"; keep the author's case.
            escaped = IssueReferencePrefix().Replace(escaped, "$1" + ZeroWidthSpace);

            var indentLength = 0;
            while (indentLength < escaped.Length && escaped[indentLength] == ' ')
            {
                indentLength++;
            }

            var indent = escaped[..indentLength];
            var body = escaped[indentLength..];
            if (body.Length > 0 && BlockStarters.Contains(body[0]))
            {
                lines[i] = indent + "\\" + body;
                continue;
            }

            // "1. x" → "1\. x": the escaped delimiter can no longer start an ordered list, which
            // could otherwise renumber or forge items in our own lists.
            lines[i] = indent + OrderedListDelimiter().Replace(body, "$1\\$2");
        }

        return string.Join("\n", lines);
    }

    /// <summary>
    /// Neutralizes the live mention and cross-reference triggers in untrusted text.
    /// </summary>
    /// <remarks>
    /// Every model- and transcript-derived field that reaches a tracker is run through this on the
    /// way out. GitHub autolinks <b>and notifies</b> <c>@mentions</c> in an issue title and in an
    /// issue body and resolves <c>#123</c> cross-references there too; a tracker can render the
    /// same text again in notifications, activity feeds and search results. A third party who
    /// only controls what is on the recorded screen could otherwise put a name in the transcript
    /// and have the user's export ping arbitrary accounts in their repository, or forge a
    /// cross-reference to an unrelated issue.
    ///
    /// Only the live triggers are defanged. The fields this is used for — a tracker's
    /// single-line title and Jira's structured ADF description — are plain text, not markdown, so
    /// the block-structure, link and entity escapes the GitHub body needs
    /// (<see cref="Neutralize"/>) would only mangle them. A line-for-line counterpart of the
    /// macOS <c>TrackerExportPayloadBudget.neutralizingUntrustedMentions</c>.
    /// </remarks>
    public static string NeutralizeMentions(string? text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text ?? string.Empty;
        }

        // A zero-width space after @/# breaks the mention and issue autolinks while leaving the
        // text visually identical.
        var neutralized = text
            .Replace("@", "@" + ZeroWidthSpace)
            .Replace("#", "#" + ZeroWidthSpace);
        // "GH-123" is an issue reference GitHub links just like "#123"; keep the author's case.
        return IssueReferencePrefix().Replace(neutralized, "$1" + ZeroWidthSpace);
    }

    [GeneratedRegex("(?i)(gh-)")]
    private static partial Regex IssueReferencePrefix();

    [GeneratedRegex(@"^(\d{1,9})([.)])(?=\s|$)")]
    private static partial Regex OrderedListDelimiter();
}
