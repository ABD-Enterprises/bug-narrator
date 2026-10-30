using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class SessionDataProtectionTests : IDisposable
{
    private const string PrivateText = "Fixture-only private transcript and review notes.";
    private readonly string root = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));
    private readonly WindowsSessionDataProtector protector = new();
    private AppStoragePaths Paths => new(root, Path.Combine(root, "Sessions"), Path.Combine(root, "Logs"));

    [Fact]
    public void Protector_RoundTripsAcrossInstancesAndRandomizesEachEnvelope()
    {
        var plaintext = Encoding.UTF8.GetBytes(PrivateText);
        var first = protector.Protect(plaintext);
        var second = protector.Protect(plaintext);

        Assert.True(first.AsSpan().StartsWith("BNWENC1\n"u8));
        Assert.False(first.SequenceEqual(second));
        Assert.DoesNotContain(PrivateText, Encoding.UTF8.GetString(first));
        Assert.Equal(plaintext, new WindowsSessionDataProtector().Unprotect(first));
        Assert.Equal(plaintext, protector.Unprotect(second));
    }

    [Fact]
    public void Protector_RoundTripsEmptyContent()
    {
        Assert.Empty(protector.Unprotect(protector.Protect([])));
    }

    [Theory]
    [InlineData("key")]
    [InlineData("nonce")]
    [InlineData("tag")]
    [InlineData("ciphertext")]
    public void Protector_RejectsTamperedEncryptedContent(string component)
    {
        var payload = protector.Protect(Encoding.UTF8.GetBytes(PrivateText));
        var keySize = BinaryPrimitives.ReadInt32LittleEndian(payload.AsSpan(8));
        var nonceOffset = 12 + keySize;
        var offset = component switch
        {
            "key" => 12,
            "nonce" => nonceOffset,
            "tag" => nonceOffset + 12,
            _ => payload.Length - 1,
        };
        payload[offset] ^= 0x80;

        Assert.ThrowsAny<CryptographicException>(() => protector.Unprotect(payload));
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(0)]
    [InlineData(int.MaxValue)]
    [InlineData(16385)]
    public void Protector_RejectsInvalidWrappedKeyLengths(int length)
    {
        var payload = protector.Protect(Encoding.UTF8.GetBytes(PrivateText));
        BinaryPrimitives.WriteInt32LittleEndian(payload.AsSpan(8), length);
        Assert.Throws<CryptographicException>(() => protector.Unprotect(payload));
    }

    [Theory]
    [InlineData(8)]
    [InlineData(11)]
    [InlineData(20)]
    public void Protector_RejectsTruncatedEnvelopes(int length)
    {
        var payload = protector.Protect(Encoding.UTF8.GetBytes(PrivateText));
        Assert.Throws<CryptographicException>(() => protector.Unprotect(payload[..length]));
    }

    [Fact]
    public async Task CompletedStore_ProtectsEveryDerivedArtifactAndUpgradesRetainedLegacyDraft()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText,
            ReviewSessionTestData.CreateIssueExtractionResult() with { Summary = PrivateText }) with { ReviewSummary = PrivateText };
        var draftPath = Path.Combine(session.SessionDirectory, "session-draft.json");
        var draftJson = JsonSerializer.Serialize(new { Title = PrivateText });
        await File.WriteAllTextAsync(draftPath, draftJson);
        var store = new FileCompletedSessionStore(Paths);

        await store.SaveAsync(session);

        foreach (var path in new[] { session.MetadataFilePath, session.TranscriptMarkdownFilePath,
                     Path.Combine(session.SessionDirectory, "summary.md"), draftPath })
        {
            var payload = await File.ReadAllBytesAsync(path);
            Assert.True(payload.AsSpan().StartsWith("BNWENC1\n"u8));
            Assert.DoesNotContain(PrivateText, Encoding.UTF8.GetString(payload));
            Assert.Contains(PrivateText, Encoding.UTF8.GetString(protector.Unprotect(payload)));
        }

        var reloaded = Assert.Single(await new FileCompletedSessionStore(Paths).GetAllAsync());
        Assert.Equal(session.TranscriptText, reloaded.TranscriptText);
        Assert.Equal(session.ReviewSummary, reloaded.ReviewSummary);
        Assert.Equal(session.IssueExtraction!.Issues[0].Title, reloaded.IssueExtraction!.Issues[0].Title);
        Assert.Equal("audio", await File.ReadAllTextAsync(session.AudioFilePath));
        Assert.Empty(Directory.EnumerateFiles(session.SessionDirectory, "*.tmp"));
    }

    [Fact]
    public async Task DraftStore_ProtectsNotesWithTheSecureDefault()
    {
        var store = new FileSessionDraftStore(Paths);
        var draft = await store.CreateDraftAsync(DateTimeOffset.UtcNow);
        await store.SaveAsync(draft with { Title = PrivateText, FailureMessage = PrivateText });

        var payload = await File.ReadAllBytesAsync(draft.MetadataFilePath);
        Assert.DoesNotContain(PrivateText, Encoding.UTF8.GetString(payload));
        Assert.Contains(PrivateText, Encoding.UTF8.GetString(protector.Unprotect(payload)));
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task CompletedStore_ReadsLegacyJsonAndUpgradesOnSave(bool withBom)
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText);
        var json = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(session));
        await File.WriteAllBytesAsync(session.MetadataFilePath, withBom ? [0xEF, 0xBB, 0xBF, .. json] : json);
        var store = new FileCompletedSessionStore(Paths);

        var legacy = Assert.Single(await store.GetAllAsync());
        Assert.Equal(PrivateText, legacy.TranscriptText);
        await store.SaveAsync(legacy);

        Assert.DoesNotContain(PrivateText, Encoding.UTF8.GetString(await File.ReadAllBytesAsync(session.MetadataFilePath)));
        Assert.Equal(PrivateText, Assert.Single(await store.GetAllAsync()).TranscriptText);
    }

    [Fact]
    public async Task CompletedStore_IsolatesCorruptEncryptedSessionWithoutOverwritingIt()
    {
        var broken = ReviewSessionTestData.CreateCompletedSession(root, PrivateText);
        var valid = ReviewSessionTestData.CreateCompletedSession(root, "Unrelated fixture transcript");
        var store = new FileCompletedSessionStore(Paths);
        await store.SaveAsync(broken);
        await store.SaveAsync(valid);
        var damaged = await File.ReadAllBytesAsync(broken.MetadataFilePath);
        damaged[^1] ^= 1;
        await File.WriteAllBytesAsync(broken.MetadataFilePath, damaged);

        Assert.Equal(valid.SessionId, Assert.Single(await store.GetAllAsync()).SessionId);
        Assert.Equal(damaged, await File.ReadAllBytesAsync(broken.MetadataFilePath));
    }

    [Fact]
    public async Task CompletedStore_EncryptionFailureDoesNotReplaceAnyExistingArtifact()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText);
        await File.WriteAllTextAsync(session.MetadataFilePath, "existing fixture metadata");
        var oldTranscript = await File.ReadAllBytesAsync(session.TranscriptMarkdownFilePath);
        var store = new FileCompletedSessionStore(Paths, new FailingProtector());

        await Assert.ThrowsAsync<CryptographicException>(() => store.SaveAsync(session));

        Assert.Equal("existing fixture metadata", await File.ReadAllTextAsync(session.MetadataFilePath));
        Assert.Equal(oldTranscript, await File.ReadAllBytesAsync(session.TranscriptMarkdownFilePath));
        Assert.Empty(Directory.EnumerateFiles(session.SessionDirectory, "*.tmp"));
    }

    [Fact]
    public async Task Export_RemainsPlaintextAfterEncryptedLibraryReload()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText,
            ReviewSessionTestData.CreateIssueExtractionResult());
        var store = new FileCompletedSessionStore(Paths);
        await store.SaveAsync(session);
        var reloaded = Assert.Single(await store.GetAllAsync());
        var exporter = new FileSessionBundleExporter(Paths, new WindowsDiagnostics(Paths));

        var bundle = await exporter.ExportAsync(reloaded);

        Assert.Contains(PrivateText, await File.ReadAllTextAsync(Path.Combine(bundle, "transcript.md")));
        Assert.Contains(session.IssueExtraction!.Issues[0].Title,
            await File.ReadAllTextAsync(Path.Combine(bundle, "summary.md")));
        Assert.False(File.Exists(Path.Combine(bundle, "session.json")));
        Assert.False(File.Exists(Path.Combine(bundle, "session-draft.json")));
        Assert.Equal(PrivateText, Assert.Single(await store.GetAllAsync()).TranscriptText);
    }

    [Fact]
    public async Task CompletedStore_RemovesStalePlaintextSummaryWhenReviewOutputIsCleared()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText);
        var summaryPath = Path.Combine(session.SessionDirectory, "summary.md");
        await File.WriteAllTextAsync(summaryPath, PrivateText);

        await new FileCompletedSessionStore(Paths).SaveAsync(session);

        Assert.False(File.Exists(summaryPath));
        Assert.Equal(PrivateText, Assert.Single(await new FileCompletedSessionStore(Paths).GetAllAsync()).TranscriptText);
    }

    [Fact]
    public async Task CompletedStore_RejectsUnreadableRetainedDraftBeforeReplacingMetadata()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, PrivateText);
        var store = new FileCompletedSessionStore(Paths);
        await store.SaveAsync(session);
        var original = await File.ReadAllBytesAsync(session.MetadataFilePath);
        var damagedDraft = protector.Protect(Encoding.UTF8.GetBytes(PrivateText));
        damagedDraft[^1] ^= 1;
        var draftPath = Path.Combine(session.SessionDirectory, "session-draft.json");
        await File.WriteAllBytesAsync(draftPath, damagedDraft);

        await Assert.ThrowsAnyAsync<CryptographicException>(() => store.SaveAsync(session with { Title = "Changed fixture" }));

        Assert.Equal(original, await File.ReadAllBytesAsync(session.MetadataFilePath));
        Assert.Equal(damagedDraft, await File.ReadAllBytesAsync(draftPath));
    }

    [Fact]
    public async Task CompletedStore_AccountsForEnvelopeOverheadAtTheMetadataLimit()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, string.Empty);
        var overhead = JsonSerializer.SerializeToUtf8Bytes(session, new JsonSerializerOptions { WriteIndented = true }).Length;
        session = session with { TranscriptText = new string('x', 4 * 1024 * 1024 - overhead) };
        var store = new FileCompletedSessionStore(Paths);

        await store.SaveAsync(session);

        Assert.True(new FileInfo(session.MetadataFilePath).Length > 4 * 1024 * 1024);
        Assert.Equal(session.TranscriptText, Assert.Single(await store.GetAllAsync()).TranscriptText);
    }

    [Fact]
    public async Task CompletedStore_RejectsOversizedMetadataBeforeWriting()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(root, new string('x', 4 * 1024 * 1024));

        await Assert.ThrowsAsync<InvalidDataException>(() => new FileCompletedSessionStore(Paths).SaveAsync(session));

        Assert.False(File.Exists(session.MetadataFilePath));
        Assert.Equal("# BugNarrator Transcript", await File.ReadAllTextAsync(session.TranscriptMarkdownFilePath));
    }

    private sealed class FailingProtector : ISessionDataProtector
    {
        private int callCount;
        public byte[] Protect(byte[] plaintext) => ++callCount == 2
            ? throw new CryptographicException("Fixture protection failure") : plaintext;
        public byte[] Unprotect(byte[] payload) => payload;
    }

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
