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
    private readonly FakeWindowsAppSettingsStore settingsStore;
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
        settingsStore = new FakeWindowsAppSettingsStore();

        service = new ReviewSessionActionService(
            completedSessionStore,
            settingsStore,
            secretStore,
            issueExtractionService,
            issueExportService,
            new FakeSessionBundleExporter(),
            new FakeDebugBundleExporter(),
            transcriptionClient,
            diagnostics);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WithAProviderNow_TranscribesThePreservedAudioAndSavesCompleted()
    {
        // Preserved at stop time with no provider: no transcript, NotConfigured.
        var preserved = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            TranscriptText = string.Empty,
            TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
        };
        await File.WriteAllBytesAsync(preserved.AudioFilePath, [0x52, 0x49, 0x46, 0x46]);
        await completedSessionStore.SaveAsync(preserved);
        Assert.True(preserved.RequiresTranscriptionRetry);

        // The user has since configured a key.
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        transcriptionClient.TranscriptText = "The checkout button is clipped.";

        var updated = await service.RetryTranscriptionAsync(preserved);

        Assert.Equal(1, transcriptionClient.CallCount);
        Assert.Equal(preserved.AudioFilePath, transcriptionClient.LastAudioFilePath);
        Assert.Equal(SessionTranscriptionStatus.Completed, updated.TranscriptionStatus);
        Assert.Equal("The checkout button is clipped.", updated.TranscriptText);
        Assert.False(updated.RequiresTranscriptionRetry);

        var saved = Assert.Single(await completedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.Completed, saved.TranscriptionStatus);
        Assert.Equal("The checkout button is clipped.", saved.TranscriptText);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WithTheProviderStillMissing_LeavesTheSessionNotConfiguredWithGuidance()
    {
        var preserved = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            TranscriptText = string.Empty,
            TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
        };
        await File.WriteAllBytesAsync(preserved.AudioFilePath, [0x52, 0x49, 0x46, 0x46]);
        await completedSessionStore.SaveAsync(preserved);
        // No key in the secret store.

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() => service.RetryTranscriptionAsync(preserved));

        Assert.Contains("AI provider", exception.Message);
        Assert.Equal(0, transcriptionClient.CallCount);
        var saved = Assert.Single(await completedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.NotConfigured, saved.TranscriptionStatus);
        Assert.True(saved.RequiresTranscriptionRetry);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WhenTheProviderFails_PersistsFailedWithTheReasonAndStaysRetryable()
    {
        var preserved = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            TranscriptText = string.Empty,
            TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
        };
        await File.WriteAllBytesAsync(preserved.AudioFilePath, [0x52, 0x49, 0x46, 0x46]);
        await completedSessionStore.SaveAsync(preserved);
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        transcriptionClient.ExceptionToThrow = new InvalidOperationException("The AI provider credential was rejected.");

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() => service.RetryTranscriptionAsync(preserved));

        Assert.Equal("The AI provider credential was rejected.", exception.Message);
        var saved = Assert.Single(await completedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.Failed, saved.TranscriptionStatus);
        Assert.Equal("The AI provider credential was rejected.", saved.TranscriptionFailureMessage);
        Assert.True(saved.RequiresTranscriptionRetry);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_WhenCancelled_PropagatesCancellationAndSavesNothing()
    {
        var preserved = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            TranscriptText = string.Empty,
            TranscriptionStatus = SessionTranscriptionStatus.NotConfigured,
        };
        await File.WriteAllBytesAsync(preserved.AudioFilePath, [0x52, 0x49, 0x46, 0x46]);
        await completedSessionStore.SaveAsync(preserved);
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        using var cancellation = new CancellationTokenSource();
        transcriptionClient.ExceptionToThrow = new OperationCanceledException(cancellation.Token);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => service.RetryTranscriptionAsync(preserved, cancellation.Token));

        var saved = Assert.Single(await completedSessionStore.GetAllAsync());
        Assert.Equal(SessionTranscriptionStatus.NotConfigured, saved.TranscriptionStatus);
        Assert.Null(saved.TranscriptionFailureMessage);
    }

    [Fact]
    public async Task RetryTranscriptionAsync_OnACompletedSession_Refuses()
    {
        var completed = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";

        await Assert.ThrowsAsync<InvalidOperationException>(() => service.RetryTranscriptionAsync(completed));
        Assert.Equal(0, transcriptionClient.CallCount);
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
        Assert.Equal("gpt-4.1-mini", issueExtractionService.LastModel);
        Assert.Equal("sk-test", issueExtractionService.LastApiKey);
    }

    [Fact]
    public async Task ExtractIssuesAsync_WithTranscriptionOnlyProvider_RefusesBeforeAnyRequest()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        secretStore.Values[SecretKeys.OpenAiApiKey] = "sk-test";
        settingsStore.AiProvider = "parakeetLocal";

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() => service.ExtractIssuesAsync(session));

        Assert.Equal(WindowsAiProviderProfile.TranscriptionOnlyGuidance, exception.Message);
        Assert.Equal(0, issueExtractionService.CallCount);
        Assert.Empty(await completedSessionStore.GetAllAsync());
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
        public int CallCount { get; private set; }

        public Task<IssueExtractionResult> ExtractAsync(
            CompletedSession session,
            string apiKey,
            string model,
            string? providerBaseUrl,
            CancellationToken cancellationToken = default)
        {
            LastApiKey = apiKey;
            LastModel = model;
            CallCount++;
            return Task.FromResult(ReviewSessionTestData.CreateIssueExtractionResult());
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

    private sealed class FakeTranscriptionClient : ITranscriptionClient
    {
        public int CallCount { get; private set; }
        public Exception? ExceptionToThrow { get; set; }
        public string? LastAudioFilePath { get; private set; }
        public string TranscriptText { get; set; } = "Retried transcript.";

        public Task<string> TranscribeToTextAsync(
            string audioFilePath,
            string apiKey,
            OpenAiTranscriptionRequest request,
            CancellationToken cancellationToken = default)
        {
            CallCount++;
            LastAudioFilePath = audioFilePath;
            if (ExceptionToThrow is not null)
            {
                throw ExceptionToThrow;
            }

            return Task.FromResult(TranscriptText);
        }

        public Task ValidateApiKeyAsync(string apiKey, string? providerBaseUrl, CancellationToken cancellationToken = default)
        {
            return Task.CompletedTask;
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
        public string AiProvider { get; set; } = WindowsAiProviderProfile.Default.StorageValue;

        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(new WindowsAppSettings(
                AiProvider: AiProvider,
                TranscriptionModel: "whisper-1",
                LanguageHint: string.Empty,
                TranscriptionPrompt: string.Empty,
                IssueExtractionModel: "gpt-4.1-mini",
                AiProviderBaseUrl: string.Empty,
                AudioInputDeviceName: string.Empty,
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
