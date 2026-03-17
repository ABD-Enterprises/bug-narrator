using System.Drawing;
using System.Drawing.Imaging;

namespace BugNarrator.Windows.Services.Capture;

public sealed class DesktopScreenshotImageCaptureService : IScreenshotImageCaptureService
{
    public async Task CaptureAsync(
        ScreenshotSelection selection,
        string destinationPath,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        await Task.Run(() =>
        {
            Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);

            using var bitmap = new Bitmap(selection.Width, selection.Height);
            using var graphics = Graphics.FromImage(bitmap);

            graphics.CopyFromScreen(
                sourceX: selection.X,
                sourceY: selection.Y,
                destinationX: 0,
                destinationY: 0,
                blockRegionSize: new Size(selection.Width, selection.Height));

            bitmap.Save(destinationPath, ImageFormat.Png);

            var fileInfo = new FileInfo(destinationPath);
            if (!fileInfo.Exists || fileInfo.Length <= 0)
            {
                throw new IOException("Screenshot capture did not produce a valid file.");
            }
        }, cancellationToken);
    }
}
