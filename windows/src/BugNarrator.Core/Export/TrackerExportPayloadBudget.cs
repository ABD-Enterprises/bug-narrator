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
    /// uses — so the cap here is exact for Jira (#1200, macOS #1112).
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
    public static string TrackerTitle(string? value, int maxCharacters)
    {
        var collapsed = string.Join(
            " ",
            (value ?? string.Empty).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (collapsed.Length <= maxCharacters)
        {
            return collapsed;
        }

        var keep = Math.Max(0, maxCharacters - 1);
        return collapsed[..keep].TrimEnd() + "…";
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
