using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// AtomicFileOperations is internal, so the no-BOM invariant is proven through every public caller
/// that reaches disk with it: the session store, the session bundle exporter, and the debug bundle
/// exporter. Testing each caller is also the point — a future caller that bypasses the helper with
/// Encoding.UTF8 would reintroduce the defect, and only a per-artifact check would catch that.
/// </summary>
public sealed class AtomicFileOperationsTests : IDisposable
{
    private static readonly byte[] Utf8Bom = [0xEF, 0xBB, 0xBF];

    private readonly string rootDirectory;
    private readonly AppStoragePaths storagePaths;
    private readonly WindowsDiagnostics diagnostics;

    public AtomicFileOperationsTests()
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

        Directory.CreateDirectory(storagePaths.SessionsDirectory);
        Directory.CreateDirectory(storagePaths.SessionBundlesDirectory);
        Directory.CreateDirectory(storagePaths.DebugBundlesDirectory);
        Directory.CreateDirectory(storagePaths.LogsDirectory);
    }

    [Fact]
    public async Task FileCompletedSessionStore_SaveAsync_WritesSessionJsonAndTranscriptWithoutBom()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        var store = new FileCompletedSessionStore(storagePaths);

        await store.SaveAsync(session);

        AssertNoBom(session.MetadataFilePath);
        AssertNoBom(session.TranscriptMarkdownFilePath);
    }

    [Fact]
    public async Task FileSessionBundleExporter_WritesEveryGeneratedTextArtifactWithoutBom()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var exporter = new FileSessionBundleExporter(storagePaths, diagnostics);

        var bundlePath = await exporter.ExportAsync(session);

        // Bounded to the generated text artifacts: copied screenshots are binary and outside the
        // UTF-8 invariant.
        AssertNoBom(Path.Combine(bundlePath, "transcript.md"));
        AssertNoBom(Path.Combine(bundlePath, "summary.md"));
        AssertNoBom(Path.Combine(bundlePath, "manifest.json"));
    }

    [Fact]
    public async Task FileDebugBundleExporter_WritesEveryFileWithoutBom()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        var exporter = new FileDebugBundleExporter(storagePaths, new FakeWindowsAppSettingsStore(), diagnostics);

        var bundlePath = await exporter.ExportAsync(session);

        var files = Directory.GetFiles(bundlePath);
        Assert.NotEmpty(files);
        foreach (var file in files)
        {
            AssertNoBom(file);
        }
    }

    private static void AssertNoBom(string path)
    {
        Assert.True(File.Exists(path), $"{path} was not written.");
        var head = new byte[3];
        using var stream = File.OpenRead(path);
        var read = stream.Read(head, 0, head.Length);
        Assert.False(
            read == 3 && head.AsSpan().SequenceEqual(Utf8Bom),
            $"{Path.GetFileName(path)} starts with a UTF-8 BOM.");
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
