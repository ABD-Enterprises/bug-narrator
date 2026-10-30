using System.Runtime.CompilerServices;
using System.Text.Json;
using BugNarrator.Windows.Services.LocalTranscription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// The bearer token the local transcription server requires (#1270).
/// </summary>
/// <remarks>
/// The token path, file name and environment variable are shared with the macOS
/// port and the Python server through a committed contract fixture, so the two
/// ports cannot drift apart silently.
/// </remarks>
public sealed class LocalServerTokenStoreTests
{
    [Fact]
    public void TheTokenPathMatchesTheSharedContractFixture()
    {
        var fixture = JsonDocument.Parse(File.ReadAllText(FixturePath())).RootElement;

        Assert.Equal(
            LocalServerTokenStore.TokenFileName,
            fixture.GetProperty("tokenFileName").GetString());
        Assert.Equal(
            LocalServerTokenStore.EnvironmentVariable,
            fixture.GetProperty("environmentVariable").GetString());
        Assert.Equal(
            LocalServerTokenStore.AuthorizationScheme,
            fixture.GetProperty("authorizationScheme").GetString());
        Assert.Equal(
            LocalServerTokenStore.ChallengeHeader,
            fixture.GetProperty("challengeHeader").GetString());
        Assert.Equal(
            LocalServerTokenStore.ProofHeader,
            fixture.GetProperty("proofHeader").GetString());

        // The three ports have to compute the same proof from the same
        // inputs, or the app and the server would never agree on it.
        var vector = fixture.GetProperty("proofVector");
        Assert.Equal(
            vector.GetProperty("proof").GetString(),
            LocalServerTokenStore.Proof(
                vector.GetProperty("nonce").GetString()!,
                vector.GetProperty("token").GetString()!));

        var relativeDirectory = fixture
            .GetProperty("windows")
            .GetProperty("directoryRelativeToLocalAppData")
            .GetString()!;

        // The fixture spells the relative directory with forward slashes so
        // that one file can describe both platforms. Join its segments with
        // this platform's separator: passing the whole string to Path.Combine
        // would build a mixed-separator expectation that the port never
        // produces, and the comparison would fail on a correct path.
        var relativeSegments = relativeDirectory.Split('/', StringSplitOptions.RemoveEmptyEntries);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var expected = Path.Combine(
            new[] { localAppData }
                .Concat(relativeSegments)
                .Append(LocalServerTokenStore.TokenFileName)
                .ToArray());

        Assert.Equal(expected, LocalServerTokenStore.TokenFilePath(LocalServerPaths.DefaultInstallDirectory));
        Assert.Equal(expected, Path.Combine(LocalServerPaths.DefaultInstallDirectory, LocalServerTokenStore.TokenFileName));
    }

    [Fact]
    public void TheTokenIsCreatedOnceAndThenReused()
    {
        var root = Path.Combine(Path.GetTempPath(), "bugnarrator-token-" + Guid.NewGuid().ToString("N"));
        try
        {
            var first = LocalServerTokenStore.Token(root);

            Assert.NotNull(first);
            Assert.False(string.IsNullOrWhiteSpace(first));
            Assert.True(File.Exists(LocalServerTokenStore.TokenFilePath(root)));

            // A second call reuses the stored token, so the app and the server
            // that reads the same file agree on it.
            Assert.Equal(first, LocalServerTokenStore.Token(root));
            Assert.Equal(first, LocalServerTokenStore.StoredToken(root));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void AStoredTokenIsReadBackUnchanged()
    {
        var root = Path.Combine(Path.GetTempPath(), "bugnarrator-token-" + Guid.NewGuid().ToString("N"));
        try
        {
            Directory.CreateDirectory(root);
            var path = LocalServerTokenStore.TokenFilePath(root);
            File.WriteAllText(path, "  a-stored-token  ");

            Assert.Equal("a-stored-token", LocalServerTokenStore.StoredToken(root));
        }
        finally
        {
            if (Directory.Exists(root))
            {
                Directory.Delete(root, recursive: true);
            }
        }
    }

    [Fact]
    public void AFreshTokenIsLongAndUrlSafe()
    {
        var token = LocalServerTokenStore.NewToken();

        Assert.True(token.Length >= 32);
        Assert.DoesNotContain('+', token);
        Assert.DoesNotContain('/', token);
        Assert.DoesNotContain('=', token);
        Assert.NotEqual(token, LocalServerTokenStore.NewToken());
    }

    private static string FixturePath([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Windows.Tests/<this file>
        var root = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(sourceFilePath)!, "..", "..", ".."));
        var path = Path.Combine(root, "contract-fixtures", "local-server-token.json");
        Assert.True(File.Exists(path), $"Missing contract fixture at {path}.");
        return path;
    }
}
