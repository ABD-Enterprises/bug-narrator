namespace BugNarrator.Windows.Services.Capture;

public interface IScreenshotSelectionOverlayService
{
    Task<ScreenshotSelectionResult> SelectRegionAsync(CancellationToken cancellationToken = default);
}
