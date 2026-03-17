namespace BugNarrator.Core.Extraction;

public sealed record ExtractedIssueDraft(
    string Title,
    string Summary,
    string? Evidence
);
