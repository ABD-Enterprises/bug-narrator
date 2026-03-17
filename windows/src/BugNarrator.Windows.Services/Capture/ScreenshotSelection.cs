namespace BugNarrator.Windows.Services.Capture;

public readonly record struct ScreenshotSelection(
    int X,
    int Y,
    int Width,
    int Height
);
