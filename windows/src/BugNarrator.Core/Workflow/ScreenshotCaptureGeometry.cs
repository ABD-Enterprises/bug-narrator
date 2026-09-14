namespace BugNarrator.Core.Workflow;

/// <summary>A rectangle in WPF device-independent pixels (DIPs).</summary>
public readonly record struct LogicalRect(double X, double Y, double Width, double Height);

/// <summary>A rectangle in physical screen pixels — what GDI CopyFromScreen and the saved PNG use.</summary>
public readonly record struct PhysicalRect(int X, int Y, int Width, int Height);

/// <summary>One monitor as the overlay sees it: its logical bounds in the virtual-screen DIP space.</summary>
public readonly record struct MonitorGeometry(LogicalRect LogicalBounds);

/// <summary>
/// The pure DIP → physical-pixel mapping behind the screenshot overlay (#1134). The overlay measures
/// a drag in DIPs over a VirtualScreen-spanning window; the capture and the PNG are in physical
/// pixels, so a 100-DIP drag on a 125 % monitor must produce a 125-pixel-wide image, not 100.
///
/// The WPF app is system-DPI-aware (no manifest opts into per-monitor V2), so one scale factor —
/// the system DPI's — applies to the whole virtual screen: Windows presents every monitor to the
/// process in that one coordinate space and bitmap-scales the overlay on monitors whose native
/// scale differs. Under that model a region crossing a monitor boundary maps with the same factor
/// on both sides, which is what <see cref="ToPhysical"/> encodes and what the tests pin. Native
/// pixels on a monitor whose scale differs from the system's need per-monitor V2 awareness and a
/// per-monitor mapping — tracked separately (WIN-041, #1186); that change replaces this class deliberately.
/// </summary>
public static class ScreenshotCaptureGeometry
{
    /// <summary>
    /// Converts a logical selection to physical pixels. Both edges are scaled and rounded, and the
    /// size is the difference, so adjacent regions tile without a one-pixel gap or overlap even for
    /// fractional mouse coordinates. A 100 × 60 DIP region at 1.25 is 125 × 75 pixels.
    /// </summary>
    public static PhysicalRect ToPhysical(LogicalRect logical, double scaleX, double scaleY)
    {
        if (scaleX <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(scaleX), "Scale factors must be positive.");
        }

        if (scaleY <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(scaleY), "Scale factors must be positive.");
        }

        var left = (int)Math.Round(logical.X * scaleX);
        var top = (int)Math.Round(logical.Y * scaleY);
        var right = (int)Math.Round((logical.X + logical.Width) * scaleX);
        var bottom = (int)Math.Round((logical.Y + logical.Height) * scaleY);
        return new PhysicalRect(left, top, right - left, bottom - top);
    }

    /// <summary>The overlay's bounds: the union of every monitor's logical bounds (SystemParameters.VirtualScreen*).</summary>
    public static LogicalRect VirtualScreen(IReadOnlyList<MonitorGeometry> monitors)
    {
        if (monitors.Count == 0)
        {
            throw new ArgumentException("At least one monitor is required.", nameof(monitors));
        }

        var left = monitors.Min(monitor => monitor.LogicalBounds.X);
        var top = monitors.Min(monitor => monitor.LogicalBounds.Y);
        var right = monitors.Max(monitor => monitor.LogicalBounds.X + monitor.LogicalBounds.Width);
        var bottom = monitors.Max(monitor => monitor.LogicalBounds.Y + monitor.LogicalBounds.Height);
        return new LogicalRect(left, top, right - left, bottom - top);
    }

    /// <summary>
    /// The physical pixels of <paramref name="selection"/> that fall on <paramref name="monitor"/>,
    /// under the single system scale. Empty (zero size) when they do not overlap. Used to prove a
    /// region crossing a monitor boundary is mapped consistently on both sides.
    /// </summary>
    public static PhysicalRect PhysicalPartOn(LogicalRect selection, MonitorGeometry monitor, double systemScale)
    {
        var bounds = monitor.LogicalBounds;
        var left = Math.Max(selection.X, bounds.X);
        var top = Math.Max(selection.Y, bounds.Y);
        var right = Math.Min(selection.X + selection.Width, bounds.X + bounds.Width);
        var bottom = Math.Min(selection.Y + selection.Height, bounds.Y + bounds.Height);
        if (right <= left || bottom <= top)
        {
            return new PhysicalRect(0, 0, 0, 0);
        }

        return ToPhysical(new LogicalRect(left, top, right - left, bottom - top), systemScale, systemScale);
    }
}
