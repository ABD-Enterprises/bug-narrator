using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public sealed record ScreenshotCaptureResult(
    ScreenshotCaptureResultStatus Status,
    string Message,
    ScreenshotArtifact? Screenshot
);
