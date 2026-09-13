using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class SessionLibraryFilterTests
{
    [Fact]
    public void RetryNeeded_SelectsExactlyTheSessionsWhoseTranscriptionDidNotComplete()
    {
        // macOS "Retry Needed" is pendingTranscription != nil: anything preserved without a finished
        // transcript. On Windows that is every status but Completed.
        var completed = Session("completed", SessionTranscriptionStatus.Completed);
        var notConfigured = Session("not-configured", SessionTranscriptionStatus.NotConfigured);
        var failed = Session("failed", SessionTranscriptionStatus.Failed);
        var query = SessionLibraryQuery.Default with { DateRange = SessionLibraryDateRange.RetryNeeded };

        var selected = SessionLibraryQueryEvaluator.Apply([completed, notConfigured, failed], query, DateTimeOffset.UtcNow);

        Assert.Equal(
            new[] { "not-configured", "failed" }.Order(),
            selected.Select(session => session.Title).Order());
    }

    [Theory]
    [InlineData(SessionTranscriptionStatus.Completed, false)]
    [InlineData(SessionTranscriptionStatus.NotConfigured, true)]
    [InlineData(SessionTranscriptionStatus.Failed, true)]
    public void RequiresTranscriptionRetry_IsTrueForEveryStatusButCompleted(SessionTranscriptionStatus status, bool expected)
    {
        Assert.Equal(expected, Session("s", status).RequiresTranscriptionRetry);
    }

    [Fact]
    public void RetryNeeded_SitsBetweenLast30DaysAndAllSessions()
    {
        // The window lists the options in enum order, and the spec (and macOS) put Retry Needed after
        // Last 30 Days and before All Sessions — so the enum order is load-bearing.
        Assert.True(SessionLibraryDateRange.Last30Days < SessionLibraryDateRange.RetryNeeded);
        Assert.True(SessionLibraryDateRange.RetryNeeded < SessionLibraryDateRange.CustomRange);
    }

    private static CompletedSession Session(string title, SessionTranscriptionStatus status)
    {
        var createdAt = new DateTimeOffset(2026, 9, 1, 12, 0, 0, TimeSpan.Zero);
        return new CompletedSession(
            SessionId: Guid.NewGuid(),
            Title: title,
            CreatedAt: createdAt,
            RecordingStartedAt: createdAt,
            RecordingStoppedAt: createdAt.AddSeconds(30),
            SessionDirectory: string.Empty,
            AudioFilePath: string.Empty,
            MetadataFilePath: string.Empty,
            TranscriptMarkdownFilePath: string.Empty,
            TranscriptText: status == SessionTranscriptionStatus.Completed ? "Transcript." : string.Empty,
            ReviewSummary: string.Empty,
            TranscriptionStatus: status,
            TranscriptionModel: "whisper-1",
            LanguageHint: "en",
            Prompt: null,
            TranscriptionFailureMessage: status == SessionTranscriptionStatus.Failed ? "Provider rejected the request." : null,
            IssueExtraction: null,
            Screenshots: [],
            TimelineMoments: []);
    }
}
