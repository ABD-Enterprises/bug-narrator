using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public sealed record ScreenshotCapturePlan(
    ScreenshotArtifact Screenshot,
    SessionTimelineMoment TimelineMoment
);
