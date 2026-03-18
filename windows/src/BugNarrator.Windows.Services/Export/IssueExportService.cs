using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Export;

public sealed class IssueExportService : IIssueExportService
{
    private readonly GitHubExportProvider gitHubProvider;
    private readonly JiraExportProvider jiraProvider;

    public IssueExportService(
        GitHubExportProvider gitHubProvider,
        JiraExportProvider jiraProvider)
    {
        this.gitHubProvider = gitHubProvider;
        this.jiraProvider = jiraProvider;
    }

    public Task<IReadOnlyList<IssueExportResult>> ExportToGitHubAsync(
        IReadOnlyList<ExtractedIssue> issues,
        CompletedSession session,
        GitHubExportConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        return gitHubProvider.ExportAsync(issues, session, configuration, cancellationToken);
    }

    public Task<IReadOnlyList<IssueExportResult>> ExportToJiraAsync(
        IReadOnlyList<ExtractedIssue> issues,
        CompletedSession session,
        JiraExportConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        return jiraProvider.ExportAsync(issues, session, configuration, cancellationToken);
    }
}
