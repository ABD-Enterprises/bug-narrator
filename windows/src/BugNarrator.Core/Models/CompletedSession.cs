namespace BugNarrator.Core.Models;

public sealed record CompletedSession(
    Guid SessionId,
    string Title,
    DateTimeOffset CreatedAt,
    DateTimeOffset RecordingStartedAt,
    DateTimeOffset RecordingStoppedAt,
    string SessionDirectory,
    string AudioFilePath,
    string MetadataFilePath,
    string TranscriptMarkdownFilePath,
    string TranscriptText,
    string ReviewSummary,
    SessionTranscriptionStatus TranscriptionStatus,
    string TranscriptionModel,
    string? LanguageHint,
    string? Prompt,
    string? TranscriptionFailureMessage,
    IssueExtractionResult? IssueExtraction,
    IReadOnlyList<ScreenshotArtifact> Screenshots,
    IReadOnlyList<SessionTimelineMoment> TimelineMoments,
    int TranscriptionRetryCount = 0,
    DateTimeOffset? LastTranscriptionRetryAt = null)
{
    public TimeSpan Duration => RecordingStoppedAt - RecordingStartedAt;

    public bool RequiresTranscriptionRetry =>
        TranscriptionStatus is SessionTranscriptionStatus.NotConfigured or SessionTranscriptionStatus.Failed;

    public bool HasGeneratedReviewSummary =>
        !string.IsNullOrWhiteSpace(IssueExtraction?.Summary);

    public string EffectiveReviewSummary =>
        HasGeneratedReviewSummary
            ? IssueExtraction!.Summary.Trim()
            : ReviewSummary;
}
