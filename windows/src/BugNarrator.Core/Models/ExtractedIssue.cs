namespace BugNarrator.Core.Models;

public sealed record ExtractedIssue(
    Guid IssueId,
    string Title,
    ExtractedIssueCategory Category,
    string Summary,
    string EvidenceExcerpt,
    double? TimestampSeconds,
    IReadOnlyList<Guid> RelatedScreenshotIds,
    double? Confidence,
    bool RequiresReview,
    bool IsSelectedForExport,
    string? SectionTitle,
    string? Note
)
{
    /// <summary>
    /// Triage severity. Declared as an init-only property rather than a positional parameter so
    /// existing `session.json` files (and existing construction sites) stay valid: absent JSON
    /// falls back to the same `Medium` default macOS uses.
    /// </summary>
    public ExtractedIssueSeverity Severity { get; init; } = ExtractedIssueSeverity.Medium;

    /// <summary>Area of the product the issue belongs to, when the model identifies one.</summary>
    public string? Component { get; init; }

    /// <summary>
    /// Stable hint used to recognize duplicate reports of the same underlying issue, as returned by
    /// the model. Prefer <see cref="EffectiveDeduplicationHint"/>, which derives one when this is
    /// absent — including for sessions saved before this field existed.
    /// </summary>
    public string? DeduplicationHint { get; init; }

    /// <summary>
    /// Ordered steps to reproduce the issue. Init-only with an empty default so sessions saved
    /// before this field existed still deserialize.
    /// </summary>
    public IReadOnlyList<IssueReproductionStep> ReproductionSteps { get; init; } =
        Array.Empty<IssueReproductionStep>();

    /// <summary>
    /// The deduplication hint that actually identifies this issue. macOS treats this as
    /// non-optional and falls back to a derived hash, so Windows does the same.
    /// </summary>
    public string EffectiveDeduplicationHint =>
        string.IsNullOrWhiteSpace(DeduplicationHint)
            ? IssueDeduplication.MakeHint(Title, Summary, EvidenceExcerpt)
            : DeduplicationHint.Trim();

    public string? ConfidenceLabel =>
        Confidence is null ? null : $"{(int)Math.Round(Confidence.Value * 100)}%";

    public string? TimestampLabel =>
        TimestampSeconds is null ? null : Workflow.SessionTimeFormatter.FormatElapsedSeconds(TimestampSeconds.Value);
}
