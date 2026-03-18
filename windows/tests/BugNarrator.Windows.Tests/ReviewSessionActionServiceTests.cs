using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class ReviewSessionActionServiceTests : IDisposable
{
    private readonly FileCompletedSessionStore completedSessionStore;
    private readonly string rootDirectory;
    private readonly FakeIssueExportService issueExportService;
    private readonly FakeIssueExtractionService issueExtractionService;
    private readonly FakeSecretStore secretStore;
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

        service = new ReviewSessionActionService(
            completedSessionStore,
            new FakeWindowsAppSettingsStore(),
            secretStore,
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
        Assert.Equal("gpt-4.1-mini", issueExtractionService.LastModel);
        Assert.Equal("sk-test", issueExtractionService.LastApiKey);
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
