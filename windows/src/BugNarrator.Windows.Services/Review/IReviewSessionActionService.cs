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

    /// <summary>
    /// Transcribes a preserved session whose transcription did not complete (provider missing or
    /// failed at stop time) with the provider configured now, and saves the result. The spec's
    /// recovery contract: restore or replace the key, then retry later.
    /// </summary>
    Task<CompletedSession> RetryTranscriptionAsync(
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
