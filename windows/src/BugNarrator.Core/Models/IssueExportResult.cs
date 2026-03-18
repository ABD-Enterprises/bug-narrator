namespace BugNarrator.Core.Models;

public sealed record IssueExportResult(
    Guid SourceIssueId,
    IssueExportDestination Destination,
    string RemoteIdentifier,
    Uri? RemoteUrl,
    DateTimeOffset ExportedAt
);
