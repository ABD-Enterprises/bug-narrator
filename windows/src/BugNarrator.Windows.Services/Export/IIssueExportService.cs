using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Export;

public interface IIssueExportService
{
    Task<IReadOnlyList<IssueExportResult>> ExportToGitHubAsync(
        IReadOnlyList<ExtractedIssue> issues,
        CompletedSession session,
        GitHubExportConfiguration configuration,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IssueExportResult>> ExportToJiraAsync(
        IReadOnlyList<ExtractedIssue> issues,
        CompletedSession session,
        JiraExportConfiguration configuration,
        CancellationToken cancellationToken = default);
}
