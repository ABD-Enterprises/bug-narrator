namespace BugNarrator.Core.Workflow;

public sealed record RecordingPreflightResult(
    RecordingPreflightStatus Status,
    bool CanStart,
    string Message
);
