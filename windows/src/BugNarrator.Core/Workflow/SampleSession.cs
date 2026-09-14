using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// The bundled demo session — the same fixture as macOS Utilities/SampleSession.swift: same id,
/// title, creation time, transcript, markers, and extracted issues, so the first thing a new user
/// sees is identical on both platforms. Text-only: no audio, no screenshots. It is added to the
/// library as a real, deletable session and carries <see cref="CompletedSession.IsSampleSession"/> so
/// every surface can label it and it can never read as the user's own recording.
/// </summary>
public static class SampleSession
{
    /// <summary>Stable id so the sample can be recognised, replaced, or removed without title matching.</summary>
    public static readonly Guid Id = Guid.Parse("5A11E000-0000-4000-8000-000000000374");

    public const string Title = "Sample session — Reports page review";

    /// <summary>Fixed so the fixture is deterministic in tests.</summary>
    public static readonly DateTimeOffset CreatedAt = DateTimeOffset.FromUnixTimeSeconds(1_760_000_000);

    public const int DurationSeconds = 96;

    public const string Model = "sample";

    public static readonly string Transcript = string.Join(
        "\n\n",
        "I'm testing the Reports page on a fresh install, signed in as a regular member rather than an admin.",
        "I'm opening Reports from the sidebar now. The table renders, and I can see the date-range picker at the top.",
        "I'm clicking Export. I expected a CSV to download. Nothing happened — no download, no error, no spinner. I clicked it twice more and still nothing.",
        "I'm changing the date range to last 90 days. This is slow — it took about eight seconds before the table repainted, and there was no loading indicator during that time, so it looked frozen.",
        "One more thing: the empty state. I filtered to a range with no data, and the table just goes blank. There's no message explaining that the filter matched nothing, so it reads like a failure rather than an empty result.",
        "Ending the test. The export button is the blocking issue; the other two are polish.");

    /// <summary>
    /// Builds the sample rooted under <paramref name="sessionsRootDirectory"/>; the caller saves it
    /// through the session store like any other session. The directory name carries the stable id.
    /// </summary>
    public static CompletedSession Make(string sessionsRootDirectory)
    {
        var directory = Path.Combine(sessionsRootDirectory, $"sample-{Id:N}");
        var stoppedAt = CreatedAt.AddSeconds(DurationSeconds);

        return new CompletedSession(
            SessionId: Id,
            Title: Title,
            CreatedAt: CreatedAt,
            RecordingStartedAt: CreatedAt,
            RecordingStoppedAt: stoppedAt,
            SessionDirectory: directory,
            AudioFilePath: Path.Combine(directory, "session.wav"),
            MetadataFilePath: Path.Combine(directory, "session.json"),
            TranscriptMarkdownFilePath: Path.Combine(directory, "transcript.md"),
            TranscriptText: Transcript,
            ReviewSummary: string.Empty,
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: Model,
            LanguageHint: null,
            Prompt: null,
            TranscriptionFailureMessage: null,
            IssueExtraction: Extraction(),
            Screenshots: [],
            TimelineMoments: Markers())
        {
            IsSampleSession = true,
        };
    }

    private static IReadOnlyList<SessionTimelineMoment> Markers()
    {
        return
        [
            Marker(1, 12, "Reports page opened"),
            Marker(2, 31, "Export produced no file"),
            Marker(3, 58, "90-day range slow to repaint"),
            Marker(4, 79, "Empty state has no message"),
        ];
    }

    private static SessionTimelineMoment Marker(int index, double elapsedSeconds, string title)
    {
        return new SessionTimelineMoment(
            MomentId: Guid.Parse($"5A11E000-0000-4000-8000-00000000{index:D4}"),
            Kind: "marker",
            CreatedAt: CreatedAt.AddSeconds(elapsedSeconds),
            ElapsedSeconds: elapsedSeconds,
            Label: title,
            RelatedScreenshotId: null);
    }

    private static IssueExtractionResult Extraction()
    {
        return new IssueExtractionResult(
            GeneratedAt: CreatedAt.AddSeconds(DurationSeconds),
            Summary: "A member-role pass over the Reports page. Export is broken outright — the button does nothing and reports no error. Two smaller findings: a long date range takes several seconds with no loading indicator, and an empty filter result renders as a blank table with no explanation.",
            GuidanceNote: "Extracted issues are draft suggestions and should be reviewed before export.",
            Issues:
            [
                Issue(1, "Export button does nothing on the Reports page", ExtractedIssueCategory.Bug, ExtractedIssueSeverity.High,
                    "Clicking Export produces no download, no error, and no spinner. Repeated clicks have no effect.",
                    "I'm clicking Export. I expected a CSV to download. Nothing happened — no download, no error, no spinner.", 31),
                Issue(2, "No loading indicator while a wide date range loads", ExtractedIssueCategory.UxIssue, ExtractedIssueSeverity.Medium,
                    "Switching to a 90-day range takes roughly eight seconds with no visible progress, so the page appears frozen.",
                    "it took about eight seconds before the table repainted, and there was no loading indicator during that time, so it looked frozen.", 58),
                Issue(3, "Empty filter result is indistinguishable from a failure", ExtractedIssueCategory.UxIssue, ExtractedIssueSeverity.Low,
                    "A date range matching no rows renders a blank table with no message, reading as an error rather than an empty result.",
                    "the table just goes blank. There's no message explaining that the filter matched nothing", 79),
            ]);
    }

    private static ExtractedIssue Issue(int index, string title, ExtractedIssueCategory category, ExtractedIssueSeverity severity, string summary, string evidence, double timestamp)
    {
        return new ExtractedIssue(
            IssueId: Guid.Parse($"5A11E000-0000-4000-8000-0000000001{index:D2}"),
            Title: title,
            Category: category,
            Summary: summary,
            EvidenceExcerpt: evidence,
            TimestampSeconds: timestamp,
            RelatedScreenshotIds: [],
            Confidence: 0.9,
            RequiresReview: true,
            IsSelectedForExport: true,
            SectionTitle: null,
            Note: null)
        {
            Severity = severity,
            Component = "Reports",
        };
    }
}
