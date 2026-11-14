namespace BugNarrator.Core.Export;

/// <summary>
/// Caps for text sent to external trackers, mirroring the macOS
/// `TrackerExportPayloadBudget` (Sources/BugNarrator/Services/TrackerExportPayloadBudget.swift).
///
/// Only the constants and helpers the reproduction-step rendering needs are ported here. Windows
/// previously applied no caps at all, which is tolerable for the flat fields but not for a nested
/// list the model controls: without a cap a single issue could push an arbitrarily large body at
/// GitHub or Jira, where macOS truncates. The marker strings match macOS exactly so an artifact
/// truncated on either platform reads the same.
/// </summary>
public static class TrackerExportPayloadBudget
{
    public const int ReproductionStepLimit = 10;
    public const int ListEntryLimit = 500;
    public const int ScreenshotListLimit = 10;

    /// <summary>
    /// Jira Cloud rejects a <c>summary</c> over 255 characters or containing a newline; GitHub
    /// rejects an issue <c>title</c> over 256. Hard server limits, unlike the body budgets, which
    /// are self-imposed. Jira counts UTF-16 code units — the same unit <see cref="string.Length"/>
    /// uses — so the cap here is exact for Jira (#1200, macOS #1112). The macOS port counts the
    /// same units now, so the two ports send the same title and neither can exceed the limit.
    /// </summary>
    public const int JiraSummaryLimit = 255;
    public const int GitHubTitleLimit = 256;

    private const string TruncationMarker = " …[truncated by BugNarrator for tracker limits]";
    private const string OmissionNotice = "Additional items were omitted by BugNarrator to fit tracker limits.";

    public static string Truncated(string value, int maxCharacters)
    {
        var trimmed = (value ?? string.Empty).Trim();
        if (trimmed.Length <= maxCharacters)
        {
            return trimmed;
        }

        // macOS reserves 36 characters for the marker before cutting.
        var keep = Math.Max(0, maxCharacters - 36);
        return trimmed[..keep].TrimEnd() + TruncationMarker;
    }

    /// <summary>
    /// A title for a tracker's single-line field: whitespace runs (including newlines) collapse to
    /// one space, the result is trimmed, and anything past <paramref name="maxCharacters"/> is cut
    /// with a single "…" — no "[truncated …]" suffix, which would consume most of a short field.
    /// </summary>
    /// <remarks>
    /// The title is untrusted text, so the mentions and cross-references in it are neutralized on
    /// the way out.
    ///
    /// The order matters, and it is the macOS order: the whitespace collapse runs first, the
    /// neutralization second, the length cap last. Swift's whitespace set includes the
    /// zero-width space, so a collapse after the neutralization would turn every zero-width
    /// space back into a plain space and the two ports would produce different titles. The cap
    /// runs last so the field the tracker receives still fits: the zero-width spaces count
    /// towards the limit, and cutting before the neutralization could push a title that was
    /// already at the cap over GitHub's 256 or Jira's 255.
    /// </remarks>
    public static string TrackerTitle(string? value, int maxCharacters)
    {
        var collapsed = CollapsingWhitespace(value);
        var neutralized = UntrustedMarkdown.NeutralizeMentions(collapsed);
        if (neutralized.Length <= maxCharacters)
        {
            return neutralized;
        }

        var keep = Math.Max(0, maxCharacters - 1);
        // Length counts UTF-16 units, so an odd cut can land between the halves of an astral
        // character (emoji) and leave a lone surrogate the JSON encoder turns into U+FFFD.
        if (keep > 0 && char.IsHighSurrogate(neutralized[keep - 1]))
        {
            keep--;
        }

        return TrimTrailingTitleWhitespace(neutralized[..keep]) + "…";
    }

    /// <summary>
    /// Every run of whitespace collapses to a single space.
    /// </summary>
    /// <remarks>
    /// The split set is the one the macOS port uses, which is exactly the set
    /// <c>char.IsWhiteSpace</c> accepts. Swift's own whitespace set also
    /// includes the zero-width space, so a title that carries one would
    /// collapse differently on the two ports, and the two ports have to send
    /// the same title.
    /// </remarks>
    public static string CollapsingWhitespace(string? value)
    {
        return string.Join(
            " ",
            (value ?? string.Empty).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
    }

    /// <summary>
    /// Trims the characters the macOS title cut trims.
    /// </summary>
    /// <remarks>
    /// This is exactly the set <c>char.IsWhiteSpace</c> accepts, plus the zero-width space.
    /// Swift's whitespace set already includes U+200B, so a title cut right after a neutralized
    /// mention ("…@") is trimmed on macOS but not on Windows, and the two ports would send
    /// different titles for the same issue.
    /// </remarks>
    private static string TrimTrailingTitleWhitespace(string value)
    {
        var end = value.Length;
        while (end > 0 && (char.IsWhiteSpace(value[end - 1]) || value[end - 1] == '\u200B'))
        {
            end--;
        }

        return value[..end];
    }

    /// <summary>
    /// Truncates each entry and appends the macOS omission notice when entries had to be dropped.
    /// </summary>
    public static IReadOnlyList<string> LimitedList(
        IReadOnlyList<string> values,
        int maxItems,
        int maxCharactersPerItem)
    {
        var limited = values
            .Take(maxItems)
            .Select(value => Truncated(value, maxCharactersPerItem))
            .ToList();

        if (values.Count > maxItems)
        {
            limited.Add(OmissionNotice);
        }

        return limited;
    }
}
