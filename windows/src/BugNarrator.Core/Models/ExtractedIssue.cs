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
    public string? ConfidenceLabel =>
        Confidence is null ? null : $"{(int)Math.Round(Confidence.Value * 100)}%";

    public string? TimestampLabel =>
        TimestampSeconds is null ? null : Workflow.SessionTimeFormatter.FormatElapsedSeconds(TimestampSeconds.Value);
}
