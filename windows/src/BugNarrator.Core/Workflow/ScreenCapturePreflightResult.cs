namespace BugNarrator.Core.Workflow;

public sealed record ScreenCapturePreflightResult(
    ScreenCapturePreflightStatus Status,
    bool CanCapture,
    string Message
);
