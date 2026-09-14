using System.Windows;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Capture;
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

        // DesktopScreenshotImageCaptureService allocates the bitmap and CopyFromScreen block from
        // the selection verbatim, so the PNG has exactly this size — never the logical one.
        var selection = new ScreenshotSelection(physical.X, physical.Y, physical.Width, physical.Height);
        Assert.Equal((expectedWidth, expectedHeight), (selection.Width, selection.Height));
        if (scale != 1.0)
        {
            Assert.NotEqual((int)logicalWidth, selection.Width);
        }
    }

    [Theory]
    [InlineData(1.25, 125, 75)]
    [InlineData(1.5, 150, 90)]
    public void Overlay_UnderEmulatedScale_ReportsTheDraggedRegionInPhysicalPixels(double scale, int expectedWidth, int expectedHeight)
    {
        // The production path: ScreenshotSelectionOverlayWindow.CompleteDrag with the window's
        // DIP → device transform emulated at the given scale. This is what the capture service
        // receives, so a miswired conversion in the overlay fails here.
        var selection = OnStaThread(() =>
        {
            var overlay = new ScreenshotSelectionOverlayWindow(() => (scale, scale));
            overlay.CompleteDrag(new Point(40, 24), new Point(140, 84));
            return overlay.SelectionResult;
        });

        Assert.NotNull(selection);
        Assert.Equal(ScreenshotSelectionStatus.Selected, selection!.Status);
        var origin = (X: (int)Math.Round((SystemParameters.VirtualScreenLeft + 40) * scale), Y: (int)Math.Round((SystemParameters.VirtualScreenTop + 24) * scale));
        Assert.Equal(origin.X, selection.Selection!.Value.X);
        Assert.Equal(origin.Y, selection.Selection.Value.Y);
        Assert.Equal(expectedWidth, selection.Selection.Value.Width);
        Assert.Equal(expectedHeight, selection.Selection.Value.Height);
    }

    [Fact]
    public void Overlay_WithATinyDrag_CancelsInsteadOfCapturing()
    {
        var selection = OnStaThread(() =>
        {
            var overlay = new ScreenshotSelectionOverlayWindow(() => (1.5, 1.5));
            overlay.CompleteDrag(new Point(10, 10), new Point(13, 13));
            return overlay.SelectionResult;
        });

        Assert.NotEqual(ScreenshotSelectionStatus.Selected, selection?.Status);
    }

    [Fact]
    public void ToPhysical_WithFractionalCoordinates_TilesAdjacentRegionsWithoutGapOrOverlap()
    {
        // Mouse positions are fractional DIPs; edges are rounded, not origin and size separately.
        var upper = new LogicalRect(10.3, 5.7, 100.4, 40.6);
        var lower = new LogicalRect(10.3, 46.3, 100.4, 30.2);

        var upperPhysical = ScreenshotCaptureGeometry.ToPhysical(upper, 1.25, 1.25);
        var lowerPhysical = ScreenshotCaptureGeometry.ToPhysical(lower, 1.25, 1.25);

        Assert.Equal(upperPhysical.Y + upperPhysical.Height, lowerPhysical.Y);
        Assert.Equal((int)Math.Round((10.3 + 100.4) * 1.25) - (int)Math.Round(10.3 * 1.25), upperPhysical.Width);
    }

    [Fact]
    public void OverlaySpansTheFullVirtualScreen_AndARegionAcrossTheBoundaryMapsConsistentlyOnBothSides()
    {
        // Primary at 100 % on the left, secondary at 150 % to its right (logical bounds in DIPs, as
        // SystemParameters reports them for a system-DPI-aware process).
        // The secondary runs at 150 % natively, but a system-DPI-aware process sees every monitor
        // through the one system scale (Windows virtualizes the rest); native secondary pixels are WIN-041 (#1186).
        var primary = new MonitorGeometry(new LogicalRect(0, 0, 1920, 1080));
        var secondary = new MonitorGeometry(new LogicalRect(1920, 0, 1707, 960));
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
        var leftMonitor = new MonitorGeometry(new LogicalRect(-1280, 0, 1280, 720));
        var primary = new MonitorGeometry(new LogicalRect(0, 0, 1920, 1080));

        var virtualScreen = ScreenshotCaptureGeometry.VirtualScreen([leftMonitor, primary]);

        Assert.Equal(new LogicalRect(-1280, 0, 3200, 1080), virtualScreen);
        Assert.Equal(new PhysicalRect(-1600, 0, 125, 125), ScreenshotCaptureGeometry.ToPhysical(new LogicalRect(-1280, 0, 100, 100), 1.25, 1.25));
    }

    [Fact]
    public void ToPhysical_RejectsANonPositiveScale()
    {
        var x = Assert.Throws<ArgumentOutOfRangeException>(() => ScreenshotCaptureGeometry.ToPhysical(new LogicalRect(0, 0, 10, 10), 0, 1));
        var y = Assert.Throws<ArgumentOutOfRangeException>(() => ScreenshotCaptureGeometry.ToPhysical(new LogicalRect(0, 0, 10, 10), 1, -1));

        Assert.Equal("scaleX", x.ParamName);
        Assert.Equal("scaleY", y.ParamName);
    }

    private static T OnStaThread<T>(Func<T> action)
    {
        T result = default!;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                result = action();
            }
            catch (Exception exception)
            {
                failure = exception;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null)
        {
            throw failure;
        }

        return result;
    }
}
