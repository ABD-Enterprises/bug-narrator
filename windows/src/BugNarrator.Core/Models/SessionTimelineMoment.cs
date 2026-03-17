namespace BugNarrator.Core.Models;

public sealed record SessionTimelineMoment(
    Guid MomentId,
    string Kind,
    DateTimeOffset CreatedAt,
    double ElapsedSeconds,
    string Label,
    Guid? RelatedScreenshotId
);
