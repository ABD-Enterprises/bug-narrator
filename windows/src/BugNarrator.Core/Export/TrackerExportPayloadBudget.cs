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
