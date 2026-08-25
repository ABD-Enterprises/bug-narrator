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
    private sealed record SharedSummaryIssue(
        string Title,
        string Category,
        string Severity,
        string Component,
        string Section,
        string TranscriptTime,
        string Confidence,
        bool RequiresReview,
        string Summary,
        string Evidence,
        string DedupHint);

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

    [Fact]
    public void SummaryMarkdownSharedSubset_MatchesTheCommittedGolden()
    {
        var goldenPath = Path.Combine(RepositoryRoot(), "contract-fixtures", "summary.golden.md");

        Assert.True(
            File.Exists(goldenPath),
            $"Missing contract fixture at {goldenPath}. It is committed at contract-fixtures/summary.golden.md; "
            + "regenerate it from macOS with BUGNARRATOR_UPDATE_CONTRACT_FIXTURES=1 if the contract intentionally changed.");

        var goldenBytes = File.ReadAllBytes(goldenPath);
        Assert.False(
            goldenBytes.Length >= 3
            && goldenBytes[0] == 0xEF
            && goldenBytes[1] == 0xBB
            && goldenBytes[2] == 0xBF,
            "summary.golden.md must not carry a UTF-8 BOM.");
        Assert.DoesNotContain((byte)'\r', goldenBytes);

        var produced = SharedSummaryFixture(CompletedSessionReviewMarkdownBuilder.Build(
            CanonicalSummarySession(),
            SessionTimeFormatter.InvariantTimestampOptions));

        Assert.Equal(goldenBytes, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(produced));
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

    private static CompletedSession CanonicalSummarySession()
    {
        var createdAt = DateTimeOffset.FromUnixTimeSeconds(1_773_759_600); // 2026-03-17T15:00:00Z

        return CanonicalSession() with
        {
            ReviewSummary = "Stop-time status text that must not appear.",
            IssueExtraction = new IssueExtractionResult(
                GeneratedAt: createdAt.AddMinutes(5),
                Summary: "The checkout button is clipped on the right at 1280 wide.",
                GuidanceNote: "Review before export.",
                Issues:
                [
                    new ExtractedIssue(
                        IssueId: Guid.Parse("22222222-2222-4222-8222-222222222222"),
                        Title: "Checkout button clipped",
                        Category: ExtractedIssueCategory.Bug,
                        Summary: "The checkout button is clipped on the right at 1280 wide.",
                        EvidenceExcerpt: "The checkout button is clipped on the right at 1280 wide.",
                        TimestampSeconds: 30,
                        RelatedScreenshotIds: [],
                        Confidence: 0.72,
                        RequiresReview: true,
                        IsSelectedForExport: false,
                        SectionTitle: "Opening Notes",
                        Note: "Investigate responsive width handling.")
                    {
                        Severity = ExtractedIssueSeverity.High,
                        Component = "Checkout",
                        DeduplicationHint = "checkout-button-clipped",
                        ReproductionSteps =
                        [
                            new IssueReproductionStep(
                                StepId: Guid.Parse("33333333-3333-4333-8333-333333333333"),
                                Instruction: "Open the checkout page at 1280px width.",
                                ExpectedResult: "The primary action remains fully visible.",
                                ActualResult: "The right edge of the checkout button is clipped.",
                                TimestampSeconds: 30,
                                ScreenshotId: null),
                        ],
                    },
                ]),
        };
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

    private static string SharedSummaryFixture(string markdown)
    {
        var lines = markdown.Split('\n');
        Assert.Equal("# BugNarrator Review Output", lines[0]);
        Assert.Contains(lines, line => line.StartsWith("- Recorded: ", StringComparison.Ordinal));

        var duration = Value(lines, "- Duration: ");
        var model = Value(lines, "- Transcript Model: ");
        var summary = SummaryBody(lines);
        var guidance = GuidanceNote(lines);
        var issues = SharedIssues(lines);

        var fixtureLines = new List<string>
        {
            "# BugNarrator Review Output",
            string.Empty,
            $"- Duration: {duration}",
            $"- Transcript Model: {model}",
            string.Empty,
            "## Summary",
            string.Empty,
            summary,
            string.Empty,
            $"> {guidance}",
            string.Empty,
            "## Shared Extracted Issue Fields",
            string.Empty,
        };

        foreach (var issue in issues)
        {
            fixtureLines.Add($"### {issue.Title}");
            fixtureLines.Add(string.Empty);
            fixtureLines.Add($"- Category: {issue.Category}");
            fixtureLines.Add($"- Severity: {issue.Severity}");
            fixtureLines.Add($"- Component: {issue.Component}");
            fixtureLines.Add($"- Section: {issue.Section}");
            fixtureLines.Add($"- Transcript Time: {issue.TranscriptTime}");
            fixtureLines.Add($"- Confidence: {issue.Confidence}");
            fixtureLines.Add($"- Requires Review: {(issue.RequiresReview ? "Yes" : "No")}");
            fixtureLines.Add($"- Summary: {issue.Summary}");
            fixtureLines.Add($"- Evidence: {issue.Evidence}");
            fixtureLines.Add($"- Dedup Hint: {issue.DedupHint}");
            fixtureLines.Add(string.Empty);
        }

        fixtureLines.RemoveAt(fixtureLines.Count - 1);
        return string.Join('\n', fixtureLines);
    }

    private static string Value(string[] lines, string prefix)
    {
        var line = Assert.Single(lines.Where(line => line.StartsWith(prefix, StringComparison.Ordinal)));
        return line[prefix.Length..];
    }

    private static string SummaryBody(string[] lines)
    {
        var summaryIndex = Array.IndexOf(lines, "## Summary");
        Assert.NotEqual(-1, summaryIndex);
        Assert.True(summaryIndex + 2 < lines.Length, "Missing summary body.");
        Assert.False(string.IsNullOrEmpty(lines[summaryIndex + 2]), "Missing summary body.");
        return lines[summaryIndex + 2];
    }

    private static string GuidanceNote(string[] lines)
    {
        var issuesHeaderIndex = Array.IndexOf(lines, "## Extracted Issues");
        Assert.NotEqual(-1, issuesHeaderIndex);

        for (var index = issuesHeaderIndex + 1; index < lines.Length; index++)
        {
            if (lines[index].StartsWith("> ", StringComparison.Ordinal))
            {
                return lines[index][2..];
            }
        }

        throw new Xunit.Sdk.XunitException("Missing guidance note.");
    }

    private static IReadOnlyList<SharedSummaryIssue> SharedIssues(string[] lines)
    {
        var issues = new List<SharedSummaryIssue>();
        for (var index = 0; index < lines.Length; index++)
        {
            if (!lines[index].StartsWith("### ", StringComparison.Ordinal))
            {
                continue;
            }

            var title = lines[index][4..];
            string? category = null;
            string? severity = null;
            string? component = null;
            string? section = null;
            string? transcriptTime = null;
            string? confidence = null;
            string? dedupHint = null;
            bool? requiresReview = null;

            index++;
            while (index < lines.Length && lines[index].StartsWith("- ", StringComparison.Ordinal))
            {
                var line = lines[index];
                category ??= StripPrefix(line, "- Category: ");
                severity ??= StripPrefix(line, "- Severity: ");
                component ??= StripPrefix(line, "- Component: ");
                section ??= StripPrefix(line, "- Section: ");
                transcriptTime ??= StripPrefix(line, "- Transcript Time: ");
                confidence ??= StripPrefix(line, "- Confidence: ");
                dedupHint ??= StripPrefix(line, "- Dedup Hint: ");
                if (line.StartsWith("- Requires Review: ", StringComparison.Ordinal))
                {
                    requiresReview = line["- Requires Review: ".Length..] switch
                    {
                        "Yes" => true,
                        "No" => false,
                        _ => throw new Xunit.Sdk.XunitException($"Malformed review flag: {line}"),
                    };
                }
                index++;
            }

            while (index < lines.Length && lines[index] == string.Empty)
            {
                index++;
            }

            Assert.True(index < lines.Length, $"Missing summary body for {title}.");
            var summary = lines[index];
            index++;

            while (index < lines.Length && lines[index] == string.Empty)
            {
                index++;
            }

            Assert.True(index < lines.Length && lines[index].StartsWith("> ", StringComparison.Ordinal), $"Missing evidence for {title}.");
            var evidence = lines[index][2..];

            Assert.NotNull(category);
            Assert.NotNull(severity);
            Assert.NotNull(component);
            Assert.NotNull(section);
            Assert.NotNull(transcriptTime);
            Assert.NotNull(confidence);
            Assert.NotNull(requiresReview);
            Assert.NotNull(dedupHint);

            issues.Add(new SharedSummaryIssue(
                Title: title,
                Category: category!,
                Severity: severity!,
                Component: component!,
                Section: section!,
                TranscriptTime: transcriptTime!,
                Confidence: confidence!,
                RequiresReview: requiresReview!.Value,
                Summary: summary,
                Evidence: evidence,
                DedupHint: dedupHint!));
        }

        Assert.NotEmpty(issues);
        return issues;
    }

    private static string? StripPrefix(string line, string prefix)
    {
        return line.StartsWith(prefix, StringComparison.Ordinal) ? line[prefix.Length..] : null;
    }
}
