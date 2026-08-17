namespace BugNarrator.Core.Models;

/// <summary>
/// One step in reproducing an extracted issue. Mirrors the macOS `IssueReproductionStep`
/// (Sources/BugNarrator/Models/IssueCoreSubtypes.swift:21), including the optional
/// expected/actual results and the optional transcript timestamp and screenshot reference.
/// </summary>
public sealed record IssueReproductionStep(
    Guid StepId,
    string Instruction,
    string? ExpectedResult,
    string? ActualResult,
    double? TimestampSeconds,
    Guid? ScreenshotId
)
{
    public string? TimestampLabel =>
        TimestampSeconds is null
            ? null
            : Workflow.SessionTimeFormatter.FormatElapsedSeconds(TimestampSeconds.Value);
}
