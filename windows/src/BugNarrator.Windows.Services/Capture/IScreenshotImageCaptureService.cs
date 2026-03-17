namespace BugNarrator.Windows.Services.Capture;

public interface IScreenshotImageCaptureService
{
    Task CaptureAsync(ScreenshotSelection selection, string destinationPath, CancellationToken cancellationToken = default);
}
