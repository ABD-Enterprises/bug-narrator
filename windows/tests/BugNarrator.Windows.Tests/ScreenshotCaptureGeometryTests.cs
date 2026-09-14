using System.Drawing;
using System.Drawing.Imaging;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Capture;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// WIN-014 checklist row 5, automation half (#1134): capture geometry under emulated DPI. The
/// overlay measures drags in DIPs; the saved PNG must be the dragged region in physical pixels.
/// </summary>
public sealed class ScreenshotCaptureGeometryTests
{
    [Theory]
    [InlineData(1.25, 100, 60, 125, 75)]
    [InlineData(1.5, 100, 60, 150, 90)]
    [InlineData(1.25, 333, 111, 416, 139)]   // rounding, not truncation: 416.25 → 416, 138.75 → 139
    [InlineData(1.0, 100, 60, 100, 60)]
    public void CaptureUnderEmulatedScale_ProducesABitmapOfTheDraggedRegionInPhysicalPixels(
        double scale, double logicalWidth, double logicalHeight, int expectedWidth, int expectedHeight)
    {
        // The overlay's drag, in DIPs, at an offset so origin scaling is exercised too.
        var logical = new LogicalRect(40, 24, logicalWidth, logicalHeight);

        var physical = ScreenshotCaptureGeometry.ToPhysical(logical, scale, scale);

        Assert.Equal((int)Math.Round(40 * scale), physical.X);
        Assert.Equal((int)Math.Round(24 * scale), physical.Y);
        Assert.Equal(expectedWidth, physical.Width);
        Assert.Equal(expectedHeight, physical.Height);

        // The capture allocates the bitmap from the physical selection, exactly as
        // DesktopScreenshotImageCaptureService does before CopyFromScreen; the PNG on disk has
        // the physical size, never the logical one.
        var selection = new ScreenshotSelection(physical.X, physical.Y, physical.Width, physical.Height);
        var path = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", $"{Guid.NewGuid():N}.png");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try
        {
            using (var bitmap = new Bitmap(selection.Width, selection.Height))
            {
                bitmap.Save(path, ImageFormat.Png);
            }

            using var saved = Image.FromFile(path);
            Assert.Equal(expectedWidth, saved.Width);
            Assert.Equal(expectedHeight, saved.Height);
            if (scale != 1.0)
            {
                Assert.NotEqual((int)logicalWidth, saved.Width);
            }
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void OverlaySpansTheFullVirtualScreen_AndARegionAcrossTheBoundaryMapsConsistentlyOnBothSides()
    {
        // Primary at 100 % on the left, secondary at 150 % to its right (logical bounds in DIPs, as
        // SystemParameters reports them for a system-DPI-aware process).
        var primary = new MonitorGeometry(new LogicalRect(0, 0, 1920, 1080), ScaleFactor: 1.0);
        var secondary = new MonitorGeometry(new LogicalRect(1920, 0, 1707, 960), ScaleFactor: 1.5);
        const double systemScale = 1.25;

        var virtualScreen = ScreenshotCaptureGeometry.VirtualScreen([primary, secondary]);
        Assert.Equal(new LogicalRect(0, 0, 3627, 1080), virtualScreen);

        // A 200 × 100 DIP drag straddling the boundary: 80 DIPs on the primary, 120 on the secondary.
        var selection = new LogicalRect(1840, 100, 200, 100);
        var whole = ScreenshotCaptureGeometry.ToPhysical(selection, systemScale, systemScale);
        var left = ScreenshotCaptureGeometry.PhysicalPartOn(selection, primary, systemScale);
        var right = ScreenshotCaptureGeometry.PhysicalPartOn(selection, secondary, systemScale);

        Assert.Equal(new PhysicalRect(2300, 125, 250, 125), whole);
        Assert.Equal(new PhysicalRect(2300, 125, 100, 125), left);
        Assert.Equal(new PhysicalRect(2400, 125, 150, 125), right);
        // The two halves tile the whole capture: no gap, no overlap, same scale on both sides.
        Assert.Equal(whole.X, left.X);
        Assert.Equal(left.X + left.Width, right.X);
        Assert.Equal(whole.Width, left.Width + right.Width);
    }

    [Fact]
    public void VirtualScreen_WithANegativeOriginMonitor_KeepsTheOffset()
    {
        // A monitor to the left of the primary has a negative logical X; the overlay's Left must be negative too.
        var leftMonitor = new MonitorGeometry(new LogicalRect(-1280, 0, 1280, 720), 1.0);
        var primary = new MonitorGeometry(new LogicalRect(0, 0, 1920, 1080), 1.0);

        var virtualScreen = ScreenshotCaptureGeometry.VirtualScreen([leftMonitor, primary]);

        Assert.Equal(new LogicalRect(-1280, 0, 3200, 1080), virtualScreen);
        Assert.Equal(new PhysicalRect(-1600, 0, 125, 125), ScreenshotCaptureGeometry.ToPhysical(new LogicalRect(-1280, 0, 100, 100), 1.25, 1.25));
    }

    [Fact]
    public void ToPhysical_RejectsANonPositiveScale()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => ScreenshotCaptureGeometry.ToPhysical(new LogicalRect(0, 0, 10, 10), 0, 1));
    }
}
