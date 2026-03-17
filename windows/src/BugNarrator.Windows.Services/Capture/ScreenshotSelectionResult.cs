namespace BugNarrator.Windows.Services.Capture;

public sealed record ScreenshotSelectionResult(
    ScreenshotSelectionStatus Status,
    ScreenshotSelection? Selection
);
