using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class ScreenshotCapturePlannerTests
{
    [Fact]
    public void CreatesDeterministicRelativePathAndTimelineMoment()
    {
        var startedAt = new DateTimeOffset(2026, 3, 17, 15, 0, 0, TimeSpan.Zero);
        var draft = new RecordingSessionDraft(
            SessionId: Guid.Parse("11111111-1111-1111-1111-111111111111"),
            Title: "Draft",
            CreatedAt: startedAt,
            RecordingStartedAt: startedAt,
            RecordingStoppedAt: null,
            SessionDirectory: @"C:\BugNarrator\Sessions\draft",
            AudioFilePath: @"C:\BugNarrator\Sessions\draft\session.wav",
            MetadataFilePath: @"C:\BugNarrator\Sessions\draft\session-draft.json",
            Screenshots: Array.Empty<ScreenshotArtifact>(),
            TimelineMoments: Array.Empty<SessionTimelineMoment>(),
            State: RecordingWorkflowState.Recording,
            FailureMessage: null);

        var plan = ScreenshotCapturePlanner.CreatePlan(
            draft,
            startedAt.AddSeconds(12),
            width: 320,
            height: 180);

        Assert.Equal("screenshots/screenshot-001.png", plan.Screenshot.RelativePath);
        Assert.Equal("Screenshot 001", plan.Screenshot.TimelineLabel);
        Assert.Equal("screenshot", plan.TimelineMoment.Kind);
        Assert.Equal(12d, plan.TimelineMoment.ElapsedSeconds);
        Assert.Equal(plan.Screenshot.ScreenshotId, plan.TimelineMoment.RelatedScreenshotId);
    }
}
