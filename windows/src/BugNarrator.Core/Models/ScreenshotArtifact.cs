namespace BugNarrator.Core.Models;

public sealed record ScreenshotArtifact(
    Guid ScreenshotId,
    string RelativePath,
    string AbsolutePath,
    DateTimeOffset CapturedAt,
    double ElapsedSeconds,
    int Width,
    int Height,
    string TimelineLabel
);
