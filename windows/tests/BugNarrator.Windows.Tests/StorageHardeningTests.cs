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

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }
}
