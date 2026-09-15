using Xunit;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Core.Tests;

/// <summary>
/// The piecewise per-monitor mapping behind WIN-041 (#1186). Pure geometry, so it runs on every OS;
/// the PerMonitorV2 manifest and per-monitor overlay windows are #1192, blocked on real hardware.
/// </summary>
public sealed class ScreenshotCaptureGeometryPerMonitorTests
{
    // Primary 1920×1080 at 100 % on the left; secondary 2560×1440 native at 150 % to its right.
    // Logical (DIP) layout: the secondary is 1707×960 DIPs starting at x = 1920.
    private static readonly MonitorGeometry Primary = MonitorGeometry.FromLogical(new LogicalRect(0, 0, 1920, 1080), 1.0);
    private static readonly MonitorGeometry Secondary = new(
        new LogicalRect(1920, 0, 1707, 960),
        new PhysicalRect(1920, 0, 2560, 1440),
        1.5);

    [Fact]
    public void BoundaryCrossingSelection_LandsInEachMonitorsNativePixels()
    {
        // 200 × 100 DIPs starting 80 DIPs before the seam: 80 on the primary, 120 on the secondary.
        var selection = new LogicalRect(1840, 100, 200, 100);

        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(selection, [Primary, Secondary]);

        Assert.Equal(2, parts.Count);
        Assert.Equal(Primary, parts[0].Monitor);
        Assert.Equal(new PhysicalRect(1840, 100, 80, 100), parts[0].Physical);
        Assert.Equal(Secondary, parts[1].Monitor);
        // 120 DIPs at 150 % are 180 native pixels, 100 DIPs tall are 150, starting at the secondary's physical origin.
        Assert.Equal(new PhysicalRect(1920, 150, 180, 150), parts[1].Physical);
    }

    [Fact]
    public void SeamBetweenMonitors_TilesWithoutGapOrOverlapInEachNativeSpace()
    {
        var selection = new LogicalRect(1900, 0, 40, 960);

        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(selection, [Primary, Secondary]);

        Assert.Equal(1920, parts[0].Physical.X + parts[0].Physical.Width);
        Assert.Equal(1920, parts[1].Physical.X);
        Assert.Equal(1440, parts[1].Physical.Y + parts[1].Physical.Height);
    }

    [Fact]
    public void SelectionEntirelyOnOneMonitor_YieldsOnePart()
    {
        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(new LogicalRect(2000, 200, 100, 50), [Primary, Secondary]);

        var part = Assert.Single(parts);
        Assert.Equal(Secondary, part.Monitor);
        Assert.Equal(new PhysicalRect(1920 + 120, 300, 150, 75), part.Physical);
    }

    [Fact]
    public void SelectionTouchingNoMonitor_YieldsNoParts()
    {
        Assert.Empty(ScreenshotCaptureGeometry.ToPhysicalPerMonitor(new LogicalRect(5000, 5000, 10, 10), [Primary, Secondary]));
    }

    [Fact]
    public void NegativeVirtualScreenOrigin_IsRespected()
    {
        var left = new MonitorGeometry(new LogicalRect(-1280, 0, 1280, 720), new PhysicalRect(-1600, 0, 1600, 900), 1.25);
        var selection = new LogicalRect(-100, 10, 200, 20);

        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(selection, [left, Primary]);

        Assert.Equal(2, parts.Count);
        // 100 DIPs from the left monitor's right edge, at 125 %: 125 pixels ending at its physical
        // right edge (0). Edges round, not sizes: top 12.5 → 12 and bottom 37.5 → 38, so 26 tall.
        Assert.Equal(new PhysicalRect(-125, 12, 125, 26), parts[0].Physical);
        Assert.Equal(new PhysicalRect(0, 10, 100, 20), parts[1].Physical);
    }

    [Fact]
    public void FractionalBoundaries_RoundEdgesNotSizes()
    {
        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(new LogicalRect(1930.3, 5.7, 100.4, 40.6), [Primary, Secondary]);

        var part = Assert.Single(parts);
        var expectedLeft = (int)Math.Round(10.3 * 1.5);
        var expectedRight = (int)Math.Round((10.3 + 100.4) * 1.5);
        Assert.Equal(new PhysicalRect(1920 + expectedLeft, (int)Math.Round(5.7 * 1.5), expectedRight - expectedLeft, (int)Math.Round((5.7 + 40.6) * 1.5) - (int)Math.Round(5.7 * 1.5)), part.Physical);
    }

    [Fact]
    public void SingleScaleArrangement_EqualsTheSystemDpiMapping()
    {
        // Under system-DPI awareness (today's mode, #1187) every monitor shares one scale and its
        // physical bounds derive from the logical ones; the piecewise mapping must then equal
        // PhysicalPartOn per monitor, so landing this before the manifest flip changes nothing.
        const double systemScale = 1.25;
        var monitors = new[]
        {
            MonitorGeometry.FromLogical(new LogicalRect(0, 0, 1920, 1080), systemScale),
            MonitorGeometry.FromLogical(new LogicalRect(1920, 0, 1707, 960), systemScale),
        };
        var selection = new LogicalRect(1840, 100, 200, 100);

        var parts = ScreenshotCaptureGeometry.ToPhysicalPerMonitor(selection, monitors);

        Assert.Equal(2, parts.Count);
        Assert.Equal(ScreenshotCaptureGeometry.PhysicalPartOn(selection, monitors[0], systemScale), parts[0].Physical);
        Assert.Equal(ScreenshotCaptureGeometry.PhysicalPartOn(selection, monitors[1], systemScale), parts[1].Physical);
    }

    [Fact]
    public void SingleMonitor_DegeneratesToToPhysical()
    {
        var monitor = MonitorGeometry.FromLogical(new LogicalRect(0, 0, 1920, 1080), 1.5);
        var selection = new LogicalRect(10, 20, 100, 60);

        var part = Assert.Single(ScreenshotCaptureGeometry.ToPhysicalPerMonitor(selection, [monitor]));

        Assert.Equal(ScreenshotCaptureGeometry.ToPhysical(selection, 1.5, 1.5), part.Physical);
    }

    [Fact]
    public void NoMonitors_Throws()
    {
        Assert.Throws<ArgumentException>(() => ScreenshotCaptureGeometry.ToPhysicalPerMonitor(new LogicalRect(0, 0, 1, 1), []));
    }
}
