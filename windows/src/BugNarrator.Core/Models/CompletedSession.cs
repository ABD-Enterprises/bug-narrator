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
    IReadOnlyList<SessionTimelineMoment> TimelineMoments)
{
    public TimeSpan Duration => RecordingStoppedAt - RecordingStartedAt;

    /// <summary>
    /// The session was preserved without a completed transcript — provider not configured, or the
    /// transcription failed — and can be transcribed later once the provider is fixed. The Windows
    /// equivalent of macOS <c>TranscriptSession.requiresTranscriptionRetry</c>
    /// (<c>pendingTranscription != nil</c>).
    /// </summary>
    public bool RequiresTranscriptionRetry => TranscriptionStatus != SessionTranscriptionStatus.Completed;

    /// <summary>
    /// The bundled demo (SampleSession). Init-only with a false default so sessions saved before the
    /// field existed load as real recordings. Every surface labels a sample so it can never read as
    /// the user's own capture (macOS TranscriptSession.isSampleSession).
    /// </summary>
    public bool IsSampleSession { get; init; }
}
