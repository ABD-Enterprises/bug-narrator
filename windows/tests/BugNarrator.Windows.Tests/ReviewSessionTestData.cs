using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Tests;

internal static class ReviewSessionTestData
{
    public static CompletedSession CreateCompletedSession(
        string rootDirectory,
        string transcriptText = "The save button is clipped in the modal.",
        IssueExtractionResult? issueExtraction = null,
        IReadOnlyList<ScreenshotArtifact>? screenshots = null)
    {
        var createdAt = new DateTimeOffset(2026, 3, 17, 15, 0, 0, TimeSpan.Zero);
        var sessionDirectory = Path.Combine(rootDirectory, "Sessions", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(sessionDirectory);

        var audioFilePath = Path.Combine(sessionDirectory, "session.wav");
        File.WriteAllText(audioFilePath, "audio");

        var metadataFilePath = Path.Combine(sessionDirectory, "session.json");
        var transcriptMarkdownFilePath = Path.Combine(sessionDirectory, "transcript.md");
        File.WriteAllText(transcriptMarkdownFilePath, "# BugNarrator Transcript");

        var screenshotList = (screenshots ?? Array.Empty<ScreenshotArtifact>())
            .Select(screenshot => RebaseScreenshotToSessionDirectory(sessionDirectory, screenshot))
            .ToArray();
        var timelineMoments = screenshotList
            .Select(screenshot => new SessionTimelineMoment(
                Guid.NewGuid(),
                Kind: "screenshot",
                CreatedAt: screenshot.CapturedAt,
                ElapsedSeconds: screenshot.ElapsedSeconds,
                Label: screenshot.TimelineLabel,
                RelatedScreenshotId: screenshot.ScreenshotId))
            .ToArray();

        return new CompletedSession(
            SessionId: Guid.NewGuid(),
            Title: "Tester reviews the save flow",
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddMinutes(2),
            SessionDirectory: sessionDirectory,
            AudioFilePath: audioFilePath,
            MetadataFilePath: metadataFilePath,
            TranscriptMarkdownFilePath: transcriptMarkdownFilePath,
            TranscriptText: transcriptText,
            ReviewSummary: "Tester reviews the save flow.",
            TranscriptionStatus: SessionTranscriptionStatus.Completed,
            TranscriptionModel: "whisper-1",
            LanguageHint: "en",
            Prompt: "Focus on UI review notes.",
            TranscriptionFailureMessage: null,
            IssueExtraction: issueExtraction,
            Screenshots: screenshotList,
            TimelineMoments: timelineMoments);
    }

    private static ScreenshotArtifact RebaseScreenshotToSessionDirectory(
        string sessionDirectory,
        ScreenshotArtifact screenshot)
    {
        var relativePath = screenshot.RelativePath.Replace('\\', '/');
        var absolutePath = Path.Combine(
            sessionDirectory,
            relativePath.Replace('/', Path.DirectorySeparatorChar));
        Directory.CreateDirectory(Path.GetDirectoryName(absolutePath)!);

        if (File.Exists(screenshot.AbsolutePath))
        {
            File.Copy(screenshot.AbsolutePath, absolutePath, overwrite: true);
        }

        return screenshot with
        {
            RelativePath = relativePath,
            AbsolutePath = absolutePath,
        };
    }

    public static ScreenshotArtifact CreateScreenshot(
        string rootDirectory,
        string fileName = "review-shot.png",
        double elapsedSeconds = 8,
        bool writeFile = true)
    {
        var capturedAt = new DateTimeOffset(2026, 3, 17, 15, 0, 8, TimeSpan.Zero);
        var screenshotsDirectory = Path.Combine(rootDirectory, "Screenshots");
        Directory.CreateDirectory(screenshotsDirectory);
        var absolutePath = Path.Combine(screenshotsDirectory, fileName);

        if (writeFile)
        {
            File.WriteAllText(absolutePath, "image");
        }

        return new ScreenshotArtifact(
            ScreenshotId: Guid.NewGuid(),
            RelativePath: Path.Combine("screenshots", fileName).Replace('\\', '/'),
            AbsolutePath: absolutePath,
            CapturedAt: capturedAt,
            ElapsedSeconds: elapsedSeconds,
            Width: 320,
            Height: 180,
            TimelineLabel: Path.GetFileNameWithoutExtension(fileName));
    }

    public static IssueExtractionResult CreateIssueExtractionResult(
        bool isSelectedForExport = true)
    {
        return new IssueExtractionResult(
            GeneratedAt: new DateTimeOffset(2026, 3, 17, 15, 5, 0, TimeSpan.Zero),
            Summary: "One draft issue was extracted.",
            GuidanceNote: "Review before export.",
            Issues:
            [
                new ExtractedIssue(
                    IssueId: Guid.NewGuid(),
                    Title: "Save button clips in the modal",
                    Category: ExtractedIssueCategory.Bug,
                    Summary: "The save button appears clipped in the modal layout.",
                    EvidenceExcerpt: "The save button is clipped.",
                    TimestampSeconds: 8,
                    RelatedScreenshotIds: Array.Empty<Guid>(),
                    Confidence: 0.74,
                    RequiresReview: true,
                    IsSelectedForExport: isSelectedForExport,
                    SectionTitle: "Save flow",
                    Note: null),
            ]);
    }
}
