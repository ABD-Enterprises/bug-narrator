using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class ReviewSessionActionServiceTests : IDisposable
{
    private readonly FileCompletedSessionStore completedSessionStore;
    private readonly string rootDirectory;
    private readonly FakeIssueExportService issueExportService;
    private readonly FakeIssueExtractionService issueExtractionService;
    private readonly FakeSecretStore secretStore;
    private readonly FakeTranscriptionClient transcriptionClient;
    private readonly ReviewSessionActionService service;

    public ReviewSessionActionServiceTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));

        var storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));
        var diagnostics = new WindowsDiagnostics(storagePaths);

        completedSessionStore = new FileCompletedSessionStore(storagePaths);
        issueExtractionService = new FakeIssueExtractionService();
        issueExportService = new FakeIssueExportService();
        secretStore = new FakeSecretStore();
        transcriptionClient = new FakeTranscriptionClient();

        service = new ReviewSessionActionService(
            completedSessionStore,
            new FakeWindowsAppSettingsStore(),
            secretStore,
            transcriptionClient,
            issueExtractionService,
            issueExportService,
            new FakeSessionBundleExporter(),
            new FakeDebugBundleExporter(),
            diagnostics);
    }

    [Fact]
    public async Task ExtractIssuesAsync_WithConfiguredApiKey_SavesUpdatedSession()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";

        var updatedSession = await service.ExtractIssuesAsync(session);
        var savedSessions = await completedSessionStore.GetAllAsync();
        var savedSession = Assert.Single(savedSessions);
        var extractedIssue = Assert.Single(updatedSession.IssueExtraction!.Issues);

        Assert.NotNull(updatedSession.IssueExtraction);
        Assert.Equal(updatedSession.SessionId, savedSession.SessionId);
        Assert.Equal("Save button clips in the modal", extractedIssue.Title);
        Assert.Equal("One draft issue was extracted.", updatedSession.ReviewSummary);
        Assert.Equal("gpt-4.1-mini", issueExtractionService.LastModel);
        Assert.Equal("sk-test", issueExtractionService.LastApiKey);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WithConfiguredApiKey_UpdatesTranscriptSummaryAndRetryMetadata()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory, transcriptText: string.Empty) with
        {
            ReviewSummary = "Recording saved locally without a transcript.",
            TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
            TranscriptionFailureMessage = null,
        };
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        transcriptionClient.TranscriptText = "Tester reopens the saved session and successfully retries transcription.";

        var updatedSession = await service.RetryTranscriptionAsync(session);
        var savedSession = Assert.Single(await completedSessionStore.GetAllAsync());

        Assert.Equal(SessionTranscriptionStatus.Completed, updatedSession.TranscriptionStatus);
        Assert.Equal("Tester reopens the saved session and successfully retries transcription.", updatedSession.TranscriptText);
        Assert.Equal("Tester reopens the saved session and successfully retries transcription", updatedSession.Title);
        Assert.Contains("Session length", updatedSession.ReviewSummary);
        Assert.Null(updatedSession.TranscriptionFailureMessage);
        Assert.Equal(1, updatedSession.TranscriptionRetryCount);
        Assert.NotNull(updatedSession.LastTranscriptionRetryAt);
        Assert.Equal(updatedSession.SessionId, savedSession.SessionId);
        Assert.Equal("whisper-1", transcriptionClient.LastRequest!.Model);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WhenTranscriptionFails_PersistsFailureAndRetryMetadata()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory, transcriptText: string.Empty) with
        {
            ReviewSummary = "Recording saved locally without a transcript.",
            TranscriptionStatus = SessionTranscriptionStatus.Failed,
            TranscriptionFailureMessage = "old failure",
        };
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        transcriptionClient.ExceptionToThrow = new InvalidOperationException("network timeout");

        var updatedSession = await service.RetryTranscriptionAsync(session);
        var savedSession = Assert.Single(await completedSessionStore.GetAllAsync());

        Assert.Equal(SessionTranscriptionStatus.Failed, updatedSession.TranscriptionStatus);
        Assert.Equal("network timeout", updatedSession.TranscriptionFailureMessage);
        Assert.Equal(1, updatedSession.TranscriptionRetryCount);
        Assert.NotNull(updatedSession.LastTranscriptionRetryAt);
        Assert.Contains("transcription failed", updatedSession.ReviewSummary, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(updatedSession.SessionId, savedSession.SessionId);
    }

    [Fact]
    public async Task ExportSelectedIssuesToGitHubAsync_UsesSelectedIssuesAndConfiguredRepository()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult(isSelectedForExport: true));
        secretStore.Values[SecretKeys.GitHubToken] = "gh-token";

        var results = await service.ExportSelectedIssuesToGitHubAsync(session);

        Assert.Equal("acme", issueExportService.LastGitHubConfiguration!.Owner);
        Assert.Equal("bugnarrator", issueExportService.LastGitHubConfiguration.Repository);
        Assert.Single(results);
        Assert.Single(issueExportService.LastExportedIssues);
    }

    [Fact]
    public async Task DeleteSessionAsync_RemovesSavedSessionDirectory()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        await completedSessionStore.SaveAsync(session);

        await service.DeleteSessionAsync(session);
        var savedSessions = await completedSessionStore.GetAllAsync();

        Assert.Empty(savedSessions);
        Assert.False(Directory.Exists(session.SessionDirectory));
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }

    private sealed class FakeIssueExtractionService : IIssueExtractionService
    {
        public string LastApiKey { get; private set; } = string.Empty;
        public string LastModel { get; private set; } = string.Empty;

        public Task<IssueExtractionResult> ExtractAsync(
            CompletedSession session,
            string apiKey,
            string model,
            CancellationToken cancellationToken = default)
        {
            LastApiKey = apiKey;
            LastModel = model;
            return Task.FromResult(ReviewSessionTestData.CreateIssueExtractionResult());
        }
    }

    private sealed class FakeTranscriptionClient : ITranscriptionClient
    {
        public Exception? ExceptionToThrow { get; set; }
        public OpenAiTranscriptionRequest? LastRequest { get; private set; }
        public string TranscriptText { get; set; } = "Transcript.";

        public Task<string> TranscribeToTextAsync(
            string audioFilePath,
            string apiKey,
            OpenAiTranscriptionRequest request,
            CancellationToken cancellationToken = default)
        {
            LastRequest = request;

            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            return Task.FromResult(TranscriptText);
        }

        public Task ValidateApiKeyAsync(string apiKey, CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
        }
    }

    private sealed class FakeIssueExportService : IIssueExportService
    {
        public IReadOnlyList<ExtractedIssue> LastExportedIssues { get; private set; } = Array.Empty<ExtractedIssue>();
        public GitHubExportConfiguration? LastGitHubConfiguration { get; private set; }

        public Task<IReadOnlyList<IssueExportResult>> ExportToGitHubAsync(
            IReadOnlyList<ExtractedIssue> issues,
            CompletedSession session,
            GitHubExportConfiguration configuration,
            CancellationToken cancellationToken = default)
        {
            LastExportedIssues = issues;
            LastGitHubConfiguration = configuration;

            IReadOnlyList<IssueExportResult> results =
            [
                new IssueExportResult(
                    SourceIssueId: issues[0].IssueId,
                    Destination: IssueExportDestination.GitHub,
                    RemoteIdentifier: "#101",
                    RemoteUrl: new Uri("https://github.com/acme/bugnarrator/issues/101"),
                    ExportedAt: DateTimeOffset.UtcNow),
            ];

            return Task.FromResult(results);
        }

        public Task<IReadOnlyList<IssueExportResult>> ExportToJiraAsync(
            IReadOnlyList<ExtractedIssue> issues,
            CompletedSession session,
            JiraExportConfiguration configuration,
            CancellationToken cancellationToken = default)
        {
            IReadOnlyList<IssueExportResult> results = Array.Empty<IssueExportResult>();
            return Task.FromResult(results);
        }
    }

    private sealed class FakeSecretStore : ISecretStore
    {
        public Dictionary<string, string?> Values { get; } = new();

        public ValueTask<string?> GetAsync(string key, CancellationToken cancellationToken = default)
        {
            Values.TryGetValue(key, out var value);
            return ValueTask.FromResult(value);
        }

        public ValueTask SetAsync(string key, string value, CancellationToken cancellationToken = default)
        {
            Values[key] = value;
            return ValueTask.CompletedTask;
        }

        public ValueTask RemoveAsync(string key, CancellationToken cancellationToken = default)
        {
            Values.Remove(key);
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeSessionBundleExporter : ISessionBundleExporter
    {
        public Task<string> ExportAsync(CompletedSession session, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(@"C:\Bundles\session");
        }
    }

    private sealed class FakeDebugBundleExporter : IDebugBundleExporter
    {
        public Task<string> ExportAsync(CompletedSession? session, CancellationToken cancellationToken = default)
        {
            return Task.FromResult(@"C:\Bundles\debug");
        }
    }

    private sealed class FakeWindowsAppSettingsStore : IWindowsAppSettingsStore
    {
        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(new WindowsAppSettings(
                TranscriptionModel: "whisper-1",
                LanguageHint: string.Empty,
                TranscriptionPrompt: string.Empty,
                IssueExtractionModel: "gpt-4.1-mini",
                GitHubRepositoryOwner: "acme",
                GitHubRepositoryName: "bugnarrator",
                GitHubDefaultLabels: "bug, triage",
                JiraBaseUrl: "https://acme.atlassian.net/",
                JiraProjectKey: "BN",
                JiraIssueType: "Task"));
        }

        public ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default)
        {
            return ValueTask.CompletedTask;
        }
    }
}
