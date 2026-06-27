namespace BugNarrator.Windows.Services.Export;

/// <summary>
/// Neutralizes untrusted (LLM-derived) text so it renders as literal content in a
/// GitHub Markdown issue body: it cannot trigger @mentions or #issue cross-links,
/// inject raw HTML, or start new block-level structure (headings, quotes, lists,
/// tables, code fences). Mirrors the macOS app's neutralizingUntrustedMarkdown (#477).
/// </summary>
public static class UntrustedMarkdown
{
    private const string ZeroWidthSpace = "\u200B";

    public static string Neutralize(string? text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text ?? string.Empty;
        }

        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            // A zero-width space after @/# breaks GitHub's mention and issue
            // autolinks (and defeats `# heading` injection) while leaving the
            // text visually identical; angle brackets become HTML entities.
            var escaped = lines[i]
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("@", "@" + ZeroWidthSpace)
                .Replace("#", "#" + ZeroWidthSpace);

            if (escaped.Length > 0 && "-*+|=`~".IndexOf(escaped[0]) >= 0)
            {
                escaped = "\\" + escaped;
            }

            lines[i] = escaped;
        }

        return string.Join("\n", lines);
    }
}
