using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class StorageHardeningTests : IDisposable
{
    private readonly string rootDirectory;
    private readonly AppStoragePaths storagePaths;

    public StorageHardeningTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));

        Directory.CreateDirectory(storagePaths.SessionsDirectory);
        Directory.CreateDirectory(storagePaths.SecretsDirectory);
        Directory.CreateDirectory(storagePaths.LogsDirectory);
    }

    [Fact]
    public async Task FileCompletedSessionStore_GetAllAsync_IgnoresScreenshotPathsOutsideTheSessionDirectory()
    {
        var sessionDirectory = Path.Combine(storagePaths.SessionsDirectory, "tampered-session");
        Directory.CreateDirectory(sessionDirectory);

        var externalFilePath = Path.Combine(rootDirectory, "External", "secret.txt");
        Directory.CreateDirectory(Path.GetDirectoryName(externalFilePath)!);
        await File.WriteAllTextAsync(externalFilePath, "top secret");

        var tamperedSession = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            SessionDirectory = sessionDirectory,
            AudioFilePath = Path.Combine(sessionDirectory, "session.wav"),
            MetadataFilePath = Path.Combine(sessionDirectory, "session.json"),
            TranscriptMarkdownFilePath = Path.Combine(sessionDirectory, "transcript.md"),
            Screenshots =
            [
                new ScreenshotArtifact(
                    Guid.NewGuid(),
                    "screenshots/secret.txt",
                    externalFilePath,
                    DateTimeOffset.UtcNow,
                    ElapsedSeconds: 3,
                    Width: 100,
                    Height: 100,
                    TimelineLabel: "Tampered"),
            ],
        };

        await File.WriteAllTextAsync(
            Path.Combine(sessionDirectory, "session.json"),
            JsonSerializer.Serialize(tamperedSession));

        var store = new FileCompletedSessionStore(storagePaths);
        var loadedSession = Assert.Single(await store.GetAllAsync());
        var screenshot = Assert.Single(loadedSession.Screenshots);

        Assert.NotEqual(externalFilePath, screenshot.AbsolutePath);
        Assert.StartsWith(sessionDirectory, screenshot.AbsolutePath);
    }

    [Fact]
    public async Task DpapiSecretStore_GetAsync_ReturnsNullForCorruptProtectedMaterial()
    {
        var diagnostics = new WindowsDiagnostics(storagePaths);
        var store = new DpapiSecretStore(storagePaths, diagnostics);
        var secretPath = Path.Combine(
            storagePaths.SecretsDirectory,
            $"{Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(SecretKeys.OpenAiApiKey)))}.secret");
        await File.WriteAllBytesAsync(secretPath, [1, 2, 3, 4, 5]);

        var value = await store.GetAsync(SecretKeys.OpenAiApiKey);

        Assert.Null(value);
    }

    /// <summary>
    /// Every session.json written before #1139 starts with a UTF-8 BOM. Those files must keep loading:
    /// the protected store must still strip the legacy BOM after decoding, so upgrading cannot
    /// silently orphan existing libraries.
    /// </summary>
    [Fact]
    public async Task FileCompletedSessionStore_GetAllAsync_LoadsSessionJsonWrittenWithABom()
    {
        var sessionDirectory = Path.Combine(storagePaths.SessionsDirectory, "legacy-bom-session");
        Directory.CreateDirectory(sessionDirectory);
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            SessionDirectory = sessionDirectory,
            AudioFilePath = Path.Combine(sessionDirectory, "session.wav"),
            MetadataFilePath = Path.Combine(sessionDirectory, "session.json"),
            TranscriptMarkdownFilePath = Path.Combine(sessionDirectory, "transcript.md"),
            Screenshots = [],
        };

        var json = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(session));
        byte[] bom = [0xEF, 0xBB, 0xBF];
        await File.WriteAllBytesAsync(Path.Combine(sessionDirectory, "session.json"), [.. bom, .. json]);

        var store = new FileCompletedSessionStore(storagePaths);
        var loaded = await store.GetAllAsync();

        var match = Assert.Single(loaded, item => item.SessionId == session.SessionId);
        Assert.Equal(session.Title, match.Title);
    }

    [Fact]
    public async Task CompletedSessionDeletion_RefusesTheEntireStorageRoot()
    {
        var sentinel = Path.Combine(storagePaths.SessionsDirectory, "keep.txt");
        await File.WriteAllTextAsync(sentinel, "synthetic session sentinel");
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            SessionDirectory = storagePaths.SessionsDirectory,
        };
        var store = new FileCompletedSessionStore(storagePaths);

        await Assert.ThrowsAsync<InvalidOperationException>(() => store.DeleteAsync(session));
        Assert.True(File.Exists(sentinel));
    }

    [Fact]
    public async Task CompletedSessionLoad_BindsPathsToTheDirectoryActuallyRead()
    {
        var actualDirectory = Path.Combine(storagePaths.SessionsDirectory, "actual-session");
        var otherDirectory = Path.Combine(storagePaths.SessionsDirectory, "other-session");
        Directory.CreateDirectory(actualDirectory);
        Directory.CreateDirectory(otherDirectory);
        var sentinel = Path.Combine(otherDirectory, "keep.txt");
        await File.WriteAllTextAsync(sentinel, "synthetic other session");
        var forged = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with
        {
            SessionDirectory = otherDirectory,
            MetadataFilePath = Path.Combine(otherDirectory, "session.json"),
        };
        await File.WriteAllTextAsync(Path.Combine(actualDirectory, "session.json"), JsonSerializer.Serialize(forged));
        var store = new FileCompletedSessionStore(storagePaths);

        var loaded = Assert.Single(await store.GetAllAsync());
        Assert.Equal(actualDirectory, loaded.SessionDirectory);
        Assert.Equal(Path.Combine(actualDirectory, "session.json"), loaded.MetadataFilePath);
        await store.DeleteAsync(loaded);
        Assert.True(File.Exists(sentinel));
    }

    [Fact]
    public async Task SessionBundleExport_ExcludesLinkedScreenshotFilesAndDirectories()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        Directory.CreateDirectory(session.SessionDirectory);
        var externalDirectory = Path.Combine(rootDirectory, "external-fixture");
        Directory.CreateDirectory(externalDirectory);
        var externalFile = Path.Combine(externalDirectory, "private.txt");
        await File.WriteAllTextAsync(externalFile, "PRIVATE_FILE_CANARY");
        var directoryLink = Path.Combine(session.SessionDirectory, "linked");
        var fileLink = Path.Combine(session.SessionDirectory, "linked.txt");
        Directory.CreateSymbolicLink(directoryLink, externalDirectory);
        File.CreateSymbolicLink(fileLink, externalFile);
        session = session with
        {
            Screenshots = new[] { "linked/private.txt", "linked.txt" }.Select(relative =>
                new ScreenshotArtifact(Guid.NewGuid(), relative, Path.Combine(session.SessionDirectory, relative),
                    DateTimeOffset.UtcNow, 1, 1, 1, "synthetic linked file")).ToArray(),
        };
        var exporter = new BugNarrator.Windows.Services.Export.FileSessionBundleExporter(
            storagePaths, new WindowsDiagnostics(storagePaths));

        var bundle = await exporter.ExportAsync(session);
        Assert.Empty(Directory.GetFiles(Path.Combine(bundle, "screenshots")));
        Assert.Equal("PRIVATE_FILE_CANARY", await File.ReadAllTextAsync(externalFile));
    }

    [Fact]
    public async Task CompletedSessionStore_RefusesLinkedSessionDirectories()
    {
        var outside = Path.Combine(rootDirectory, "outside-session");
        Directory.CreateDirectory(outside);
        var link = Path.Combine(storagePaths.SessionsDirectory, "linked-session");
        Directory.CreateSymbolicLink(link, outside);
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory) with { SessionDirectory = link };
        await File.WriteAllTextAsync(Path.Combine(outside, "session.json"), JsonSerializer.Serialize(session));
        var sentinel = Path.Combine(outside, "keep.txt");
        await File.WriteAllTextAsync(sentinel, "synthetic external data");
        var store = new FileCompletedSessionStore(storagePaths);

        Assert.Empty(await store.GetAllAsync());
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.SaveAsync(session));
        await Assert.ThrowsAsync<InvalidOperationException>(() => store.DeleteAsync(session));
        Assert.True(File.Exists(sentinel));
    }

    [Fact]
    public async Task CompletedSessionLoad_RefusesALinkedDefaultAudioFile()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        var outside = Path.Combine(rootDirectory, "private-audio-fixture.wav");
        await File.WriteAllTextAsync(outside, "PRIVATE_AUDIO_CANARY");
        File.Delete(session.AudioFilePath);
        File.CreateSymbolicLink(session.AudioFilePath, outside);
        await File.WriteAllTextAsync(session.MetadataFilePath, JsonSerializer.Serialize(session));
        var store = new FileCompletedSessionStore(storagePaths);

        Assert.Empty(await store.GetAllAsync());
        Assert.Equal("PRIVATE_AUDIO_CANARY", await File.ReadAllTextAsync(outside));
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }
}
