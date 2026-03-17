using BugNarrator.Core.Workflow;

namespace BugNarrator.Core.Models;

public sealed record RecordingSessionDraft(
    Guid SessionId,
    string Title,
    DateTimeOffset CreatedAt,
    DateTimeOffset RecordingStartedAt,
    DateTimeOffset? RecordingStoppedAt,
    string SessionDirectory,
    string AudioFilePath,
    string MetadataFilePath,
    IReadOnlyList<ScreenshotArtifact> Screenshots,
    IReadOnlyList<SessionTimelineMoment> TimelineMoments,
    RecordingWorkflowState State,
    string? FailureMessage
);
