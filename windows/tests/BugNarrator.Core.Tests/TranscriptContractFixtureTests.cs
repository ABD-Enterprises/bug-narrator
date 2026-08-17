using System.Runtime.CompilerServices;
using System.Text;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

/// <summary>
/// Binds the Windows renderer to the shared contract fixture that macOS generates.
///
/// Before this existed each platform compared its output to its own hand-typed literal, so both
/// suites could be green while the implementations disagreed — see contract-fixtures/README.md and
/// the false green it documents. The golden is loaded, never retyped.
/// </summary>
public sealed class TranscriptContractFixtureTests
{
    [Fact]
    public void TranscriptMarkdown_MatchesTheCommittedGolden()
    {
        var goldenPath = Path.Combine(RepositoryRoot(), "contract-fixtures", "transcript.golden.md");

        // Fail loudly rather than silently skipping: a missing fixture means the contract is not
        // being checked at all, which is exactly the state this test exists to end.
        Assert.True(
            File.Exists(goldenPath),
            $"Missing contract fixture at {goldenPath}. It is committed at contract-fixtures/transcript.golden.md; "
            + "regenerate it from macOS with BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 if the contract intentionally changed.");

        var golden = File.ReadAllText(goldenPath);

        // A CRLF checkout makes the byte comparison fail in a way that looks impossible: the text is
        // identical on screen. Name the real cause instead of leaving an inscrutable diff.
        Assert.False(
            golden.Contains('\r'),
            "The contract fixture was checked out with CRLF line endings. contract-fixtures/** is pinned to "
            + "eol=lf in .gitattributes; re-checkout the file (git rm --cached + git checkout) so it is LF on disk.");
        var produced = CompletedSessionMarkdownBuilder.Build(
            CanonicalSession(),
            SessionTimeFormatter.InvariantTimestampOptions);

        // Byte-for-byte. contract-fixtures/** is pinned to eol=lf in .gitattributes so this does not
        // depend on the checkout's core.autocrlf setting.
        // String comparison first: it produces a readable diff when the contract drifts.
        Assert.Equal(golden, produced);

        // Then the actual bytes. File.ReadAllText decodes and silently consumes a BOM, so a
        // BOM-tagged fixture would pass the comparison above while the committed bytes differ —
        // and "byte-for-byte" is the guarantee this fixture exists to provide.
        Assert.Equal(
            File.ReadAllBytes(goldenPath),
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(produced));
    }

    /// <summary>
    /// The canonical session from contract-fixtures/README.md, built from the documented field
    /// values so both platforms render the same input.
    /// </summary>
    private static CompletedSession CanonicalSession()
    {
        var createdAt = DateTimeOffset.FromUnixTimeSeconds(1_773_759_600); // 2026-03-17T15:00:00Z

        return new CompletedSession(
            SessionId: Guid.Parse("00000000-0000-4000-8000-000000000001"),
            Title: "Checkout button clipped",
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddSeconds(120),
            SessionDirectory: string.Empty,
            AudioFilePath: string.Empty,
            MetadataFilePath: string.Empty,
            TranscriptMarkdownFilePath: string.Empty,
            TranscriptText: "The checkout button is clipped on the right at 1280 wide.",
            ReviewSummary: string.Empty,
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: "whisper-1",
            LanguageHint: "en",
            Prompt: null,
            TranscriptionFailureMessage: null,
            IssueExtraction: null,
            Screenshots: [],
            TimelineMoments:
            [
                new SessionTimelineMoment(
                    MomentId: Guid.Parse("11111111-1111-4111-8111-111111111111"),
                    Kind: "marker",
                    CreatedAt: createdAt.AddSeconds(30),
                    ElapsedSeconds: 30,
                    Label: "Checkout button clipped",
                    RelatedScreenshotId: null)
                {
                    Note = "Right edge is cut off at 1280 wide.",
                },
            ]);
    }

    /// <summary>
    /// Resolves the repository root from this source file's compile-time path, mirroring how the
    /// macOS fixture test uses <c>#filePath</c>. More robust than the test binary's working
    /// directory, and it cannot go stale the way a copied-to-output fixture can.
    /// </summary>
    private static string RepositoryRoot([CallerFilePath] string sourceFilePath = "")
    {
        // <root>/windows/tests/BugNarrator.Core.Tests/<this file>
        var directory = Path.GetDirectoryName(sourceFilePath)!;
        return Path.GetFullPath(Path.Combine(directory, "..", "..", ".."));
    }
}
