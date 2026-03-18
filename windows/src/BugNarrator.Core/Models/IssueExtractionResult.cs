namespace BugNarrator.Core.Models;

public sealed record IssueExtractionResult(
    DateTimeOffset GeneratedAt,
    string Summary,
    string GuidanceNote,
    IReadOnlyList<ExtractedIssue> Issues)
{
    public IReadOnlyList<ExtractedIssue> SelectedIssues =>
        Issues.Where(issue => issue.IsSelectedForExport).ToArray();
}
