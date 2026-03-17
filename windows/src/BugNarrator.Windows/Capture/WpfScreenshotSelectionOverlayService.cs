using BugNarrator.Windows.Services.Capture;
using System.Windows;

namespace BugNarrator.Windows.Capture;

public sealed class WpfScreenshotSelectionOverlayService : IScreenshotSelectionOverlayService
{
    public Task<ScreenshotSelectionResult> SelectRegionAsync(CancellationToken cancellationToken = default)
    {
        return Application.Current.Dispatcher.InvokeAsync(() =>
        {
            using var registration = cancellationToken.Register(() =>
            {
                Application.Current.Dispatcher.BeginInvoke(() =>
                {
                    foreach (Window window in Application.Current.Windows)
                    {
                        if (window is ScreenshotSelectionOverlayWindow overlayWindow)
                        {
                            overlayWindow.CancelSelection();
                        }
                    }
                });
            });

            var overlay = new ScreenshotSelectionOverlayWindow();
            overlay.ShowDialog();
            return overlay.SelectionResult;
        }).Task;
    }
}
