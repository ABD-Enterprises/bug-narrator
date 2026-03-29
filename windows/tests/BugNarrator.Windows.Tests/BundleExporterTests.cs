using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class BundleExporterTests : IDisposable
{
    private readonly string rootDirectory;
    private readonly AppStoragePaths storagePaths;
    private readonly WindowsDiagnostics diagnostics;

    public BundleExporterTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));
        diagnostics = new WindowsDiagnostics(storagePaths);

        Directory.CreateDirectory(storagePaths.SessionBundlesDirectory);
        Directory.CreateDirectory(storagePaths.DebugBundlesDirectory);
        Directory.CreateDirectory(storagePaths.LogsDirectory);
    }

    [Fact]
    public async Task FileSessionBundleExporter_ExportsTranscriptAndScreenshots()
    {
        var screenshot = ReviewSessionTestData.CreateScreenshot(rootDirectory);
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            screenshots: [screenshot]);
        await File.WriteAllTextAsync(session.TranscriptMarkdownFilePath, "# Transcript\n\nExample");

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        Assert.True(File.Exists(Path.Combine(bundlePath, "transcript.md")));
        Assert.True(File.Exists(Path.Combine(bundlePath, "screenshots", Path.GetFileName(screenshot.AbsolutePath))));
    }

    [Fact]
    public async Task FileDebugBundleExporter_WritesExpectedFilesWithoutSecrets()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        diagnostics.Info("export", "Authorization: Bearer fixture-openai-key fixture-github-pat");

        var exporter = new FileDebugBundleExporter(
            storagePaths,
            new FakeWindowsAppSettingsStore(),
            diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        Assert.True(File.Exists(Path.Combine(bundlePath, "system-info.json")));
        Assert.True(File.Exists(Path.Combine(bundlePath, "app-version.txt")));
        Assert.True(File.Exists(Path.Combine(bundlePath, "windows-version.txt")));
        Assert.True(File.Exists(Path.Combine(bundlePath, "recent-log.txt")));
        Assert.True(File.Exists(Path.Combine(bundlePath, "session-metadata.json")));

        var sessionMetadata = await File.ReadAllTextAsync(Path.Combine(bundlePath, "session-metadata.json"));
        Assert.Contains("\"issueCount\": 1", sessionMetadata);
        Assert.DoesNotContain("fixture-openai-key", sessionMetadata, StringComparison.OrdinalIgnoreCase);

        var recentLog = await File.ReadAllTextAsync(Path.Combine(bundlePath, "recent-log.txt"));
        Assert.Contains("[REDACTED]", recentLog, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("fixture-openai-key", recentLog, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("fixture-github-pat", recentLog, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task FileSessionBundleExporter_DoesNotCopyScreenshotPathsOutsideTheSessionDirectory()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        Directory.CreateDirectory(session.SessionDirectory);

        var externalFilePath = Path.Combine(rootDirectory, "External", "secret.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(externalFilePath)!);
        await File.WriteAllTextAsync(externalFilePath, "sensitive");

        var tamperedSession = session with
        {
            Screenshots =
            [
                new BugNarrator.Core.Models.ScreenshotArtifact(
                    Guid.NewGuid(),
                    "screenshots/secret.txt",
                    externalFilePath,
                    DateTimeOffset.UtcNow,
                    ElapsedSeconds: 5,
                    Width: 100,
                    Height: 100,
                    TimelineLabel: "Tampered screenshot"),
            ],
        };

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(tamperedSession);

        Assert.Empty(Directory.GetFiles(Path.Combine(bundlePath, "screenshots")));
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }

    private sealed class FakeWindowsAppSettingsStore : IWindowsAppSettingsStore
    {
        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(WindowsAppSettings.Default);
        }

        public ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default)
        {
            return ValueTask.CompletedTask;
        }
    }
}
