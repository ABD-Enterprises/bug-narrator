namespace BugNarrator.Core.Models;

public sealed record SessionTimelineMoment(
    Guid MomentId,
    string Kind,
    DateTimeOffset CreatedAt,
    double ElapsedSeconds,
    string Label,
    Guid? RelatedScreenshotId
)
{
    /// <summary>
    /// Optional note shown after the marker label, matching the macOS `SessionMarker.note`.
    /// Init-only with a null default so sessions saved before this field existed still deserialize.
    /// </summary>
    public string? Note { get; init; }
}
