using System.Runtime.CompilerServices;
using System.Text.Json;
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
    public async Task FileSessionBundleExporter_CopiesAnnotatedExports()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        var annotatedExportsDirectory = Path.Combine(session.SessionDirectory, "annotated-exports");
        Directory.CreateDirectory(annotatedExportsDirectory);
        await File.WriteAllBytesAsync(Path.Combine(annotatedExportsDirectory, "review-shot-annotated-12345678.png"), [1, 2, 3]);

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        Assert.True(File.Exists(Path.Combine(bundlePath, "annotated-exports", "review-shot-annotated-12345678.png")));
    }

    [Fact]
    public async Task FileSessionBundleExporter_RegeneratesTranscriptInsteadOfCopyingStaleFile()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        // A transcript.md written by an earlier build still carries the pre-parity contract.
        await File.WriteAllTextAsync(
            session.TranscriptMarkdownFilePath,
            "# Stale Transcript\n\n## Review Summary\n\nStale superset content.");

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        var transcript = await File.ReadAllTextAsync(Path.Combine(bundlePath, "transcript.md"));

        Assert.DoesNotContain("Stale superset content.", transcript);
        Assert.DoesNotContain("## Review Summary", transcript);
        Assert.Contains("# BugNarrator Transcript", transcript);
        Assert.Contains("## Raw Transcript", transcript);
    }

    [Fact]
    public async Task FileSessionBundleExporter_WritesSummaryWhenReviewOutputExists()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        var summaryPath = Path.Combine(bundlePath, "summary.md");
        Assert.True(File.Exists(summaryPath));

        var summary = await File.ReadAllTextAsync(summaryPath);
        Assert.Contains("# BugNarrator Review Output", summary);
        Assert.Contains("## Extracted Issues", summary);
    }

    [Fact]
    public async Task FileSessionBundleExporter_OmitsSummaryWhenThereIsNoReviewOutput()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            ReviewSummary = string.Empty,
            IssueExtraction = null,
        };

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        Assert.False(File.Exists(Path.Combine(bundlePath, "summary.md")));
    }

    [Fact]
    public async Task FileSessionBundleExporter_OmitsSummaryForAReviewSummaryOnlySession()
    {
        // Behavior change: a session with a review summary but no extraction used to get a
        // summary.md on Windows. macOS writes one only when extraction ran, and Windows now matches.
        // The review summary itself is unaffected — it stays in session.json and the session library.
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            ReviewSummary = "Tester reviews the save flow.",
            IssueExtraction = null,
        };

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        Assert.False(File.Exists(Path.Combine(bundlePath, "summary.md")));
        // The transcript is still exported.
        Assert.True(File.Exists(Path.Combine(bundlePath, "transcript.md")));
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

    /// <summary>
    /// The bundle layout is a shared contract: contract-fixtures/session-bundle-layout.json is the
    /// same file Tests/BugNarratorTests/TranscriptExporterTests.swift reads on macOS. Reading it here
    /// rather than restating its entries means both platforms fail together when the layout changes.
    /// </summary>
    [Fact]
    public async Task FileSessionBundleExporter_MatchesTheSharedBundleLayoutFixture()
    {
        var layoutPath = Path.Combine(RepositoryRoot(), "contract-fixtures", "session-bundle-layout.json");
        Assert.True(
            File.Exists(layoutPath),
            $"Missing contract fixture at {layoutPath}. It is committed at contract-fixtures/session-bundle-layout.json.");

        using var layout = JsonDocument.Parse(await File.ReadAllBytesAsync(layoutPath));
        var always = layout.RootElement.GetProperty("always").EnumerateArray().Select(entry => entry.GetString()!).ToArray();
        var whenExtracted = layout.RootElement.GetProperty("whenIssueExtractionHasRun").EnumerateArray().Select(entry => entry.GetString()!).ToArray();
        Assert.NotEmpty(always);
        Assert.NotEmpty(whenExtracted);

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);

        var withoutExtraction = await exporter.ExportAsync(
            ReviewSessionTestData.CreateCompletedSession(rootDirectory));
        foreach (var entry in always)
        {
            Assert.True(LayoutEntryExists(withoutExtraction, entry), $"{entry} is listed under always but is absent from the bundle.");
        }

        foreach (var entry in whenExtracted)
        {
            Assert.False(LayoutEntryExists(withoutExtraction, entry), $"{entry} must not be written when issue extraction has not run.");
        }

        var withExtraction = await exporter.ExportAsync(
            ReviewSessionTestData.CreateCompletedSession(
                rootDirectory,
                issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult()));
        foreach (var entry in always.Concat(whenExtracted))
        {
            Assert.True(LayoutEntryExists(withExtraction, entry), $"{entry} is absent from a bundle exported after extraction ran.");
        }
    }

    [Fact]
    public async Task FileSessionBundleExporter_ManifestListsEveryFileWrittenInTheMacOrder()
    {
        var present = ReviewSessionTestData.CreateScreenshot(rootDirectory, "present-capture.png", elapsedSeconds: 4);
        var missing = ReviewSessionTestData.CreateScreenshot(rootDirectory, "missing-capture.png", elapsedSeconds: 9, writeFile: false);
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult(),
            screenshots: [present, missing]);

        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var bundlePath = await exporter.ExportAsync(session);

        var manifestBytes = await File.ReadAllBytesAsync(Path.Combine(bundlePath, "manifest.json"));
        // Raw bytes on purpose. File.ReadAllText would silently consume a BOM, and a BOM is exactly the
        // defect this guards against: RFC 8259 §8.1 forbids one, macOS writes none, and
        // JsonDocument.Parse rejects it. (The class-wide fix at AtomicFileOperations is #1139.)
        Assert.False(
            manifestBytes.Length >= 3 && manifestBytes[0] == 0xEF && manifestBytes[1] == 0xBB && manifestBytes[2] == 0xBF,
            "manifest.json starts with a UTF-8 BOM.");
        using var manifest = JsonDocument.Parse(manifestBytes);
        var root = manifest.RootElement;

        // The exact key set macOS writes (SessionBundleManifest in TranscriptExporter.swift). A key
        // added on one platform only would break the "reads the same" promise, so this is exact.
        Assert.Equal(
            ["copiedScreenshotCount", "exportedFiles", "generatedAt", "missingScreenshots", "notes", "screenshotCount", "sessionID"],
            root.EnumerateObject().Select(property => property.Name).ToArray());

        var exportedFiles = root.GetProperty("exportedFiles").EnumerateArray().Select(entry => entry.GetString()!).ToArray();
        Assert.Equal(
            ["transcript.md", "summary.md", "screenshots/present-capture.png", "manifest.json"],
            exportedFiles);

        // exportedFiles must agree with what is actually on disk — a manifest that lists a file the
        // bundle does not contain, or omits one it does, is worse than no manifest.
        var onDisk = Directory.EnumerateFiles(bundlePath, "*", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(bundlePath, path).Replace('\\', '/'))
            .OrderBy(path => path, StringComparer.Ordinal)
            .ToArray();
        Assert.Equal(exportedFiles.OrderBy(path => path, StringComparer.Ordinal).ToArray(), onDisk);

        Assert.Equal(2, root.GetProperty("screenshotCount").GetInt32());
        Assert.Equal(1, root.GetProperty("copiedScreenshotCount").GetInt32());
        Assert.Equal(["missing-capture.png"], root.GetProperty("missingScreenshots").EnumerateArray().Select(entry => entry.GetString()!).ToArray());
        Assert.Equal(session.SessionId.ToString().ToUpperInvariant(), root.GetProperty("sessionID").GetString());
        Assert.True(DateTimeOffset.TryParse(root.GetProperty("generatedAt").GetString(), out _));
        Assert.Equal(2, root.GetProperty("notes").GetArrayLength());
    }

    private static bool LayoutEntryExists(string bundlePath, string entry)
    {
        return entry.EndsWith('/')
            ? Directory.Exists(Path.Combine(bundlePath, entry.TrimEnd('/')))
            : File.Exists(Path.Combine(bundlePath, entry));
    }

    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
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
