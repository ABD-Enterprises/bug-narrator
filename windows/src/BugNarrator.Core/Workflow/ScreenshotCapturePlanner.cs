using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public static class ScreenshotCapturePlanner
{
    public static ScreenshotCapturePlan CreatePlan(
        RecordingSessionDraft draft,
        DateTimeOffset capturedAt,
        int width,
        int height)
    {
        var nextIndex = draft.Screenshots.Count + 1;
        var fileName = $"screenshot-{nextIndex:000}.png";
        var relativePath = $"screenshots/{fileName}";
        var absolutePath = Path.Combine(draft.SessionDirectory, "screenshots", fileName);
        var elapsedSeconds = Math.Max(0, (capturedAt - draft.RecordingStartedAt).TotalSeconds);
        var screenshotId = Guid.NewGuid();
        var label = $"Screenshot {nextIndex:000}";

        var screenshot = new ScreenshotArtifact(
            screenshotId,
            relativePath,
            absolutePath,
            capturedAt,
            elapsedSeconds,
            width,
            height,
            label);

        var timelineMoment = new SessionTimelineMoment(
            Guid.NewGuid(),
            Kind: "screenshot",
            CreatedAt: capturedAt,
            ElapsedSeconds: elapsedSeconds,
            Label: label,
            RelatedScreenshotId: screenshotId);

        return new ScreenshotCapturePlan(screenshot, timelineMoment);
    }
}
