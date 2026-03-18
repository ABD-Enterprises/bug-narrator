using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Review;

public interface IReviewSessionActionService
{
    Task<CompletedSession> SaveSessionAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task DeleteSessionAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task<CompletedSession> ExtractIssuesAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToGitHubAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToJiraAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task<string> ExportSessionBundleAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);

    Task<string> ExportDebugBundleAsync(
        CompletedSession? session,
        CancellationToken cancellationToken = default);
}
