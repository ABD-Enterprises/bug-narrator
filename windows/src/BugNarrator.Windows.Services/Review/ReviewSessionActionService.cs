using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Review;

public sealed class ReviewSessionActionService : IReviewSessionActionService
{
    private readonly ICompletedSessionStore completedSessionStore;
    private readonly IDebugBundleExporter debugBundleExporter;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IIssueExportService issueExportService;
    private readonly IIssueExtractionService issueExtractionService;
    private readonly ISecretStore secretStore;
    private readonly ISessionBundleExporter sessionBundleExporter;
    private readonly IWindowsAppSettingsStore settingsStore;

    public ReviewSessionActionService(
        ICompletedSessionStore completedSessionStore,
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        IIssueExtractionService issueExtractionService,
        IIssueExportService issueExportService,
        ISessionBundleExporter sessionBundleExporter,
        IDebugBundleExporter debugBundleExporter,
        WindowsDiagnostics diagnostics)
    {
        this.completedSessionStore = completedSessionStore;
        this.settingsStore = settingsStore;
        this.secretStore = secretStore;
        this.issueExtractionService = issueExtractionService;
        this.issueExportService = issueExportService;
        this.sessionBundleExporter = sessionBundleExporter;
        this.debugBundleExporter = debugBundleExporter;
        this.diagnostics = diagnostics;
    }

    public async Task<CompletedSession> SaveSessionAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        await completedSessionStore.SaveAsync(session, cancellationToken);
        diagnostics.Info("review", $"saved completed session {session.SessionId}");
        return session;
    }

    public async Task DeleteSessionAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        await completedSessionStore.DeleteAsync(session, cancellationToken);
        diagnostics.Info("review", $"deleted completed session {session.SessionId}");
    }

    public async Task<CompletedSession> ExtractIssuesAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(session.TranscriptText))
        {
            throw new InvalidOperationException("Issue extraction requires a completed transcript.");
        }

        var apiKey = await secretStore.GetAsync(SecretKeys.OpenAiApiKey, cancellationToken);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException(
                "Add an OpenAI API key in Settings before running issue extraction.");
        }

        var settings = await settingsStore.LoadAsync(cancellationToken);
        var extraction = await issueExtractionService.ExtractAsync(
            session,
            apiKey,
            settings.EffectiveIssueExtractionModel,
            cancellationToken);

        var updatedSession = session with
        {
            IssueExtraction = extraction,
        };

        await completedSessionStore.SaveAsync(updatedSession, cancellationToken);
        diagnostics.Info(
            "review",
            $"saved extracted issues for session {session.SessionId} ({extraction.Issues.Count} issue(s))");
        return updatedSession;
    }

    public async Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToGitHubAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        var extraction = session.IssueExtraction
                         ?? throw new InvalidOperationException(
                             "Run issue extraction before exporting to GitHub.");
        var selectedIssues = extraction.SelectedIssues;
        if (selectedIssues.Count == 0)
        {
            throw new InvalidOperationException("Select at least one extracted issue before exporting to GitHub.");
        }

        var settings = await settingsStore.LoadAsync(cancellationToken);
        var token = await secretStore.GetAsync(SecretKeys.GitHubToken, cancellationToken);
        var configuration = settings.CreateGitHubExportConfiguration(token)
                           ?? throw new InvalidOperationException(
                               "GitHub export requires a token, repository owner, and repository name in Settings.");

        return await issueExportService.ExportToGitHubAsync(
            selectedIssues,
            session,
            configuration,
            cancellationToken);
    }

    public async Task<IReadOnlyList<IssueExportResult>> ExportSelectedIssuesToJiraAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        var extraction = session.IssueExtraction
                         ?? throw new InvalidOperationException(
                             "Run issue extraction before exporting to Jira.");
        var selectedIssues = extraction.SelectedIssues;
        if (selectedIssues.Count == 0)
        {
            throw new InvalidOperationException("Select at least one extracted issue before exporting to Jira.");
        }

        var settings = await settingsStore.LoadAsync(cancellationToken);
        var email = await secretStore.GetAsync(SecretKeys.JiraEmail, cancellationToken);
        var apiToken = await secretStore.GetAsync(SecretKeys.JiraApiToken, cancellationToken);
        var configuration = settings.CreateJiraExportConfiguration(email, apiToken)
                           ?? throw new InvalidOperationException(
                               "Jira export requires a base URL, email, API token, project key, and issue type in Settings.");

        return await issueExportService.ExportToJiraAsync(
            selectedIssues,
            session,
            configuration,
            cancellationToken);
    }

    public Task<string> ExportSessionBundleAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        return sessionBundleExporter.ExportAsync(session, cancellationToken);
    }

    public Task<string> ExportDebugBundleAsync(
        CompletedSession? session,
        CancellationToken cancellationToken = default)
    {
        return debugBundleExporter.ExportAsync(session, cancellationToken);
    }
}
