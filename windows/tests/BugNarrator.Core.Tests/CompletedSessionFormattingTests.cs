using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class CompletedSessionFormattingTests
{

    [Fact]
    public void CompletedSessionMarkdownBuilder_RendersPromptAndScreenshotsExactly()
    {
        // Supplementary Windows coverage, NOT a macOS contract assertion — the shared fixture in
        // TranscriptContractFixtureTests owns that. The canonical fixture session has no prompt and
        // no screenshots, so without this the exact rendering of those two blocks is untested and a
        // regression (dropping "- Prompt:", omitting "## Screenshots", reordering) could pass.
        var markdown = CompletedSessionMarkdownBuilder.Build(
            CreateReviewSession(),
            SessionTimeFormatter.InvariantTimestampOptions);

        var expected = string.Join("\n",
        [
            "# BugNarrator Transcript",
            "",
            "- Recorded: Mar 17, 2026 at 3:00:00 PM",
            "- Duration: 02:00",
            "- Model: whisper-1",
            "- Language Hint: en",
            "- Prompt: Focus on testing narration.",
            "",
            "## Markers",
            "",
            "- **Screenshot 001** at `00:12`",
            "",
            "## Screenshots",
            "",
            "- **screenshot-001.png** at `00:12`",
            "",
            "## Raw Transcript",
            "",
            "Tester opens Settings and validates the API key.",
        ]);

        Assert.Equal(expected, markdown);
    }

    [Fact]
    public void CompletedSessionMarkdownBuilder_OmitsReviewOutputFromTranscript()
    {
        var markdown = CompletedSessionMarkdownBuilder.Build(
            CreateReviewSession(),
            SessionTimeFormatter.InvariantTimestampOptions);

        Assert.DoesNotContain("## Review Summary", markdown);
        Assert.DoesNotContain("## Extracted Issues", markdown);
    }

    [Fact]
    public void CompletedSessionReviewMarkdownBuilder_PreservesReviewSummary()
    {
        var review = CompletedSessionReviewMarkdownBuilder.Build(
            CreateReviewSession(),
            SessionTimeFormatter.InvariantTimestampOptions);

        var expected = string.Join("\n",
        [
            "# BugNarrator Review Output",
            "",
            "- Recorded: Mar 17, 2026 at 3:00:00 PM",
            "- Duration: 02:00",
            "- Transcript Model: whisper-1",
            "",
            "## Summary",
            "",
            "Tester validates the OpenAI API key before starting a new review pass.",
            "",
            "Issue extraction has not been run for this session yet.",
        ]);

        Assert.Equal(expected, review);
    }

    [Fact]
    public void SessionTimelineMoment_DeserializesSessionJsonSavedBeforeTheNoteFieldExisted()
    {
        // Shape persisted by an earlier build: no Note. Property casing mirrors
        // FileCompletedSessionStore's serializer options (defaults: PascalCase, numeric enums).
        var json =
            """
            {
              "MomentId": "44444444-4444-4444-4444-444444444444",
              "Kind": "screenshot",
              "CreatedAt": "2026-03-17T15:00:12+00:00",
              "ElapsedSeconds": 12,
              "Label": "Screenshot 001",
              "RelatedScreenshotId": null
            }
            """;

        var moment = System.Text.Json.JsonSerializer.Deserialize<SessionTimelineMoment>(json);

        Assert.NotNull(moment);
        Assert.Equal("Screenshot 001", moment!.Label);
        Assert.Null(moment.Note);
    }

    [Fact]
    public void ExtractedIssue_DeserializesSessionJsonSavedBeforeTheParityFieldsExisted()
    {
        // Shape of an issue persisted by an earlier build: no Severity/Component/DeduplicationHint.
        // Property casing and the numeric enum mirror FileCompletedSessionStore's serializer options.
        var json =
            """
            {
              "IssueId": "55555555-5555-5555-5555-555555555555",
              "Title": "Save button clips",
              "Category": 0,
              "Summary": "The save button is clipped.",
              "EvidenceExcerpt": "clipped",
              "TimestampSeconds": 12,
              "RelatedScreenshotIds": [],
              "Confidence": 0.8,
              "RequiresReview": true,
              "IsSelectedForExport": true,
              "SectionTitle": null,
              "Note": null
            }
            """;

        var issue = System.Text.Json.JsonSerializer.Deserialize<ExtractedIssue>(json);

        Assert.NotNull(issue);
        Assert.Equal(ExtractedIssueSeverity.Medium, issue!.Severity);
        Assert.Null(issue.Component);
        Assert.Null(issue.DeduplicationHint);
        // Old sessions still get a usable identity for duplicate detection.
        Assert.StartsWith("issue-", issue.EffectiveDeduplicationHint);
        // Reproduction steps did not exist when this shape was written.
        Assert.Empty(issue.ReproductionSteps);
    }

    [Fact]
    public void SessionTimeFormatter_FormatsHoursWithoutLeadingZeroLikeMac()
    {
        Assert.Equal("1:05:09", SessionTimeFormatter.FormatDuration(TimeSpan.FromSeconds(3909)));
        Assert.Equal("02:00", SessionTimeFormatter.FormatDuration(TimeSpan.FromSeconds(120)));
    }

    private static CompletedSession CreateReviewSession()
    {
        var createdAt = new DateTimeOffset(2026, 3, 17, 15, 0, 0, TimeSpan.Zero);

        return new CompletedSession(
            SessionId: Guid.Parse("22222222-2222-2222-2222-222222222222"),
            Title: "Tester opens Settings",
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddMinutes(2),
            SessionDirectory: @"C:\BugNarrator\Sessions\example",
            AudioFilePath: @"C:\BugNarrator\Sessions\example\session.wav",
            MetadataFilePath: @"C:\BugNarrator\Sessions\example\session.json",
            TranscriptMarkdownFilePath: @"C:\BugNarrator\Sessions\example\transcript.md",
            TranscriptText: "Tester opens Settings and validates the API key.",
            ReviewSummary: "Tester validates the OpenAI API key before starting a new review pass.",
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: "whisper-1",
            LanguageHint: "en",
            Prompt: "Focus on testing narration.",
            TranscriptionFailureMessage: null,
            IssueExtraction: null,
            Screenshots:
            [
                new ScreenshotArtifact(
                    Guid.Parse("33333333-3333-3333-3333-333333333333"),
                    "screenshots/screenshot-001.png",
                    @"C:\BugNarrator\Sessions\example\screenshots\screenshot-001.png",
                    createdAt.AddSeconds(12),
                    ElapsedSeconds: 12,
                    Width: 320,
                    Height: 180,
                    TimelineLabel: "Screenshot 001"),
            ],
            TimelineMoments:
            [
                new SessionTimelineMoment(
                    Guid.Parse("44444444-4444-4444-4444-444444444444"),
                    Kind: "screenshot",
                    CreatedAt: createdAt.AddSeconds(12),
                    ElapsedSeconds: 12,
                    Label: "Screenshot 001",
                    RelatedScreenshotId: Guid.Parse("33333333-3333-3333-3333-333333333333")),
            ]);
    }

    [Fact]
    public void CompletedSessionMarkdownBuilder_IncludesSummaryTranscriptAndScreenshots()
    {
        var createdAt = new DateTimeOffset(2026, 3, 17, 15, 0, 0, TimeSpan.Zero);
        var session = new CompletedSession(
            SessionId: Guid.Parse("22222222-2222-2222-2222-222222222222"),
            Title: "Tester opens Settings",
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddMinutes(2),
            SessionDirectory: @"C:\BugNarrator\Sessions\example",
            AudioFilePath: @"C:\BugNarrator\Sessions\example\session.wav",
            MetadataFilePath: @"C:\BugNarrator\Sessions\example\session.json",
            TranscriptMarkdownFilePath: @"C:\BugNarrator\Sessions\example\transcript.md",
            TranscriptText: "Tester opens Settings and validates the API key.",
            ReviewSummary: "Tester validates the OpenAI API key before starting a new review pass.",
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: "whisper-1",
            LanguageHint: "en",
            Prompt: "Focus on testing narration.",
            TranscriptionFailureMessage: null,
            IssueExtraction: null,
            Screenshots:
            [
                new ScreenshotArtifact(
                    Guid.Parse("33333333-3333-3333-3333-333333333333"),
                    "screenshots/screenshot-001.png",
                    @"C:\BugNarrator\Sessions\example\screenshots\screenshot-001.png",
                    createdAt.AddSeconds(12),
                    ElapsedSeconds: 12,
                    Width: 320,
                    Height: 180,
                    TimelineLabel: "Screenshot 001"),
            ],
            TimelineMoments:
            [
                new SessionTimelineMoment(
                    Guid.Parse("44444444-4444-4444-4444-444444444444"),
                    Kind: "screenshot",
                    CreatedAt: createdAt.AddSeconds(12),
                    ElapsedSeconds: 12,
                    Label: "Screenshot 001",
                    RelatedScreenshotId: Guid.Parse("33333333-3333-3333-3333-333333333333")),
            ]);

        var markdown = CompletedSessionMarkdownBuilder.Build(session);

        Assert.Contains("# BugNarrator Transcript", markdown);
        Assert.Contains("screenshots/screenshot-001.png".Split('/')[1], markdown);
        Assert.Contains("## Raw Transcript", markdown);
        Assert.Contains("Tester opens Settings and validates the API key.", markdown);
    }

    [Fact]
    public void SessionLibraryQueryEvaluator_FiltersAndSearchesCompletedSessions()
    {
        var now = new DateTimeOffset(2026, 3, 17, 12, 0, 0, TimeSpan.Zero);
        var matchingSession = CreateSession(
            Guid.Parse("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"),
            now.AddHours(-2),
            "Tester validates Settings",
            "Tester validates the OpenAI API key.");
        var oldSession = CreateSession(
            Guid.Parse("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"),
            now.AddDays(-8),
            "Old run",
            "Older transcript.");

        var result = SessionLibraryQueryEvaluator.Apply(
            [matchingSession, oldSession],
            new SessionLibraryQuery(
                SearchText: "validates",
                DateRange: SessionLibraryDateRange.Last7Days,
                SortOrder: SessionLibrarySortOrder.NewestFirst),
            now);

        var session = Assert.Single(result);
        Assert.Equal(matchingSession.SessionId, session.SessionId);
    }

    [Fact]
    public void SessionLibraryQueryEvaluator_SearchesExtractedIssueContent()
    {
        var now = new DateTimeOffset(2026, 3, 17, 12, 0, 0, TimeSpan.Zero);
        var session = CreateSession(
            Guid.Parse("cccccccc-cccc-cccc-cccc-cccccccccccc"),
            now.AddHours(-1),
            "Review pass",
            "Transcript text.") with
        {
            IssueExtraction = new IssueExtractionResult(
                GeneratedAt: now,
                Summary: "One issue was extracted.",
                GuidanceNote: "Review before export.",
                Issues:
                [
                    new ExtractedIssue(
                        IssueId: Guid.Parse("dddddddd-dddd-dddd-dddd-dddddddddddd"),
                        Title: "Save button clips in the modal",
                        Category: ExtractedIssueCategory.Bug,
                        Summary: "The save button appears clipped in the modal layout.",
                        EvidenceExcerpt: "The save button is clipped",
                        TimestampSeconds: 8,
                        RelatedScreenshotIds: Array.Empty<Guid>(),
                        Confidence: 0.74,
                        RequiresReview: true,
                        IsSelectedForExport: true,
                        SectionTitle: "Save flow",
                        Note: null),
                ]),
        };

        var result = SessionLibraryQueryEvaluator.Apply(
            [session],
            new SessionLibraryQuery(
                SearchText: "clipped",
                DateRange: SessionLibraryDateRange.All,
                SortOrder: SessionLibrarySortOrder.NewestFirst),
            now);

        Assert.Single(result);
    }

    [Fact]
    public void SessionLibraryQueryEvaluator_SupportsYesterdayAndLast30DaysFilters()
    {
        var now = new DateTimeOffset(2026, 3, 17, 12, 0, 0, TimeSpan.Zero);
        var yesterdaySession = CreateSession(
            Guid.Parse("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"),
            now.AddDays(-1).AddHours(-2),
            "Yesterday run",
            "Captured yesterday.");
        var olderSession = CreateSession(
            Guid.Parse("ffffffff-ffff-ffff-ffff-ffffffffffff"),
            now.AddDays(-12),
            "Recent run",
            "Captured within the last month.");
        var oldestSession = CreateSession(
            Guid.Parse("11111111-1111-1111-1111-111111111111"),
            now.AddDays(-45),
            "Archived run",
            "Too old for the last 30 days filter.");

        var yesterdayResult = SessionLibraryQueryEvaluator.Apply(
            [yesterdaySession, olderSession, oldestSession],
            new SessionLibraryQuery(
                SearchText: string.Empty,
                DateRange: SessionLibraryDateRange.Yesterday,
                SortOrder: SessionLibrarySortOrder.NewestFirst),
            now);
        var last30DaysResult = SessionLibraryQueryEvaluator.Apply(
            [yesterdaySession, olderSession, oldestSession],
            new SessionLibraryQuery(
                SearchText: string.Empty,
                DateRange: SessionLibraryDateRange.Last30Days,
                SortOrder: SessionLibrarySortOrder.NewestFirst),
            now);

        Assert.Single(yesterdayResult);
        Assert.Equal(yesterdaySession.SessionId, yesterdayResult[0].SessionId);
        Assert.Equal(2, last30DaysResult.Count);
        Assert.DoesNotContain(last30DaysResult, session => session.SessionId == oldestSession.SessionId);
    }

    [Fact]
    public void SessionLibraryQueryEvaluator_UsesInclusiveCustomRangeEvenWhenDatesAreReversed()
    {
        var now = new DateTimeOffset(2026, 3, 17, 12, 0, 0, TimeSpan.Zero);
        var inRangeSession = CreateSession(
            Guid.Parse("12121212-1212-1212-1212-121212121212"),
            new DateTimeOffset(2026, 3, 10, 8, 0, 0, TimeSpan.Zero),
            "In range",
            "Inside the custom range.");
        var outOfRangeSession = CreateSession(
            Guid.Parse("34343434-3434-3434-3434-343434343434"),
            new DateTimeOffset(2026, 3, 5, 8, 0, 0, TimeSpan.Zero),
            "Out of range",
            "Outside the custom range.");

        var result = SessionLibraryQueryEvaluator.Apply(
            [inRangeSession, outOfRangeSession],
            new SessionLibraryQuery(
                SearchText: string.Empty,
                DateRange: SessionLibraryDateRange.CustomRange,
                SortOrder: SessionLibrarySortOrder.NewestFirst,
                CustomRangeStart: new DateTime(2026, 3, 12),
                CustomRangeEnd: new DateTime(2026, 3, 8)),
            now);

        var session = Assert.Single(result);
        Assert.Equal(inRangeSession.SessionId, session.SessionId);
    }

    private static CompletedSession CreateSession(
        Guid id,
        DateTimeOffset createdAt,
        string title,
        string transcriptText)
    {
        return new CompletedSession(
            SessionId: id,
            Title: title,
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddMinutes(1),
            SessionDirectory: @"C:\BugNarrator\Sessions\example",
            AudioFilePath: @"C:\BugNarrator\Sessions\example\session.wav",
            MetadataFilePath: @"C:\BugNarrator\Sessions\example\session.json",
            TranscriptMarkdownFilePath: @"C:\BugNarrator\Sessions\example\transcript.md",
            TranscriptText: transcriptText,
            ReviewSummary: transcriptText,
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: "whisper-1",
            LanguageHint: null,
            Prompt: null,
            TranscriptionFailureMessage: null,
            IssueExtraction: null,
            Screenshots: Array.Empty<ScreenshotArtifact>(),
            TimelineMoments: Array.Empty<SessionTimelineMoment>());
    }
}
