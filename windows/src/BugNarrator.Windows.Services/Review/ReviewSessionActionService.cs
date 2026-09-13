using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;

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
    private readonly ITranscriptionClient transcriptionClient;

    public ReviewSessionActionService(
        ICompletedSessionStore completedSessionStore,
        IWindowsAppSettingsStore settingsStore,
        ISecretStore secretStore,
        IIssueExtractionService issueExtractionService,
        IIssueExportService issueExportService,
        ISessionBundleExporter sessionBundleExporter,
        IDebugBundleExporter debugBundleExporter,
        ITranscriptionClient transcriptionClient,
        WindowsDiagnostics diagnostics)
    {
        this.completedSessionStore = completedSessionStore;
        this.transcriptionClient = transcriptionClient;
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

    public async Task<CompletedSession> RetryTranscriptionAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        if (!session.RequiresTranscriptionRetry)
        {
            throw new InvalidOperationException("This session already has a completed transcript.");
        }

        if (!File.Exists(session.AudioFilePath))
        {
            throw new InvalidOperationException("The session audio file is missing, so transcription cannot be retried.");
        }

        // Same resolution the lifecycle service performs at stop time (RecordingLifecycleService
        // .BuildCompletedSessionAsync); the difference is that a missing provider is an error here
        // rather than a NotConfigured save, because the user asked for a retry.
        var settings = await settingsStore.LoadAsync(cancellationToken);
        var apiKey = await secretStore.GetAsync(SecretKeys.OpenAiApiKey, cancellationToken);
        var providerCredential = settings.AiProviderCredentialForWorkflow(apiKey);
        if (providerCredential is null)
        {
            throw new InvalidOperationException(
                settings.AiProviderCompatibilityIssue
                ?? "Finish AI provider setup in Settings before retrying transcription.");
        }

        var request = new OpenAiTranscriptionRequest(
            settings.EffectiveTranscriptionModel,
            settings.EffectiveLanguageHint,
            settings.EffectiveTranscriptionPrompt,
            settings.EffectiveAiProviderBaseUrl);

        diagnostics.Info("transcription", $"transcription retry requested for session {session.SessionId} using model {request.Model}");
        CompletedSession updatedSession;
        try
        {
            var transcriptText = await transcriptionClient.TranscribeToTextAsync(
                session.AudioFilePath,
                providerCredential,
                request,
                cancellationToken);
            updatedSession = session with
            {
                TranscriptText = transcriptText,
                TranscriptionStatus = SessionTranscriptionStatus.Completed,
                TranscriptionModel = request.Model,
                LanguageHint = request.LanguageHint,
                Prompt = request.Prompt,
                TranscriptionFailureMessage = null,
            };
            diagnostics.Info("transcription", "transcription retry completed");
        }
        catch (Exception exception)
        {
            // Persist the failure exactly as stop time does, so the library keeps showing the session
            // under Retry Needed with the current reason, then surface it to the caller.
            diagnostics.Error("transcription", "transcription retry failed", exception);
            var failedSession = session with
            {
                TranscriptionStatus = SessionTranscriptionStatus.Failed,
                TranscriptionFailureMessage = exception.Message,
            };
            await completedSessionStore.SaveAsync(failedSession, cancellationToken);
            throw new InvalidOperationException(exception.Message, exception);
        }

        await completedSessionStore.SaveAsync(updatedSession, cancellationToken);
        return updatedSession;
    }

    public async Task<CompletedSession> ExtractIssuesAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(session.TranscriptText))
        {
            throw new InvalidOperationException("Issue extraction requires a completed transcript.");
        }

        var settings = await settingsStore.LoadAsync(cancellationToken);
        var apiKey = await secretStore.GetAsync(SecretKeys.OpenAiApiKey, cancellationToken);
        var providerCredential = settings.AiProviderCredentialForWorkflow(apiKey);
        if (providerCredential is null)
        {
            throw new InvalidOperationException(
                settings.AiProviderCompatibilityIssue
                ?? "Finish AI provider setup in Settings before running issue extraction.");
        }

        var extraction = await issueExtractionService.ExtractAsync(
            session,
            providerCredential,
            settings.EffectiveIssueExtractionModel,
            settings.EffectiveAiProviderBaseUrl,
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
