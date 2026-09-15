namespace BugNarrator.Core.Workflow;

/// <summary>A rectangle in WPF device-independent pixels (DIPs).</summary>
public readonly record struct LogicalRect(double X, double Y, double Width, double Height);

/// <summary>A rectangle in physical screen pixels — what GDI CopyFromScreen and the saved PNG use.</summary>
public readonly record struct PhysicalRect(int X, int Y, int Width, int Height);

/// <summary>
/// One monitor: its logical bounds in the DIP space the overlay measures drags in, its physical
/// bounds in the virtual screen (EnumDisplayMonitors), and its native scale. Under system-DPI
/// awareness every monitor shares one scale and <see cref="FromLogical"/> derives the physical
/// bounds; under PerMonitorV2 the physical bounds are authoritative and each monitor has its own
/// scale (#1186).
/// </summary>
public readonly record struct MonitorGeometry(LogicalRect LogicalBounds, PhysicalRect PhysicalBounds, double Scale)
{
    /// <summary>A monitor at 100 %: physical bounds equal the logical ones. Keeps the #1187 call sites unchanged.</summary>
    public MonitorGeometry(LogicalRect logicalBounds)
        : this(logicalBounds, ScreenshotCaptureGeometry.ToPhysical(logicalBounds, 1, 1), 1)
    {
    }

    /// <summary>A monitor whose physical bounds are its logical bounds at <paramref name="scale"/>.</summary>
    public static MonitorGeometry FromLogical(LogicalRect logicalBounds, double scale) =>
        new(logicalBounds, ScreenshotCaptureGeometry.ToPhysical(logicalBounds, scale, scale), scale);
}

/// <summary>The part of a selection that falls on one monitor, in that monitor's native pixels.</summary>
public readonly record struct MonitorPart(MonitorGeometry Monitor, PhysicalRect Physical);

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
/// per-monitor mapping — <see cref="ToPhysicalPerMonitor"/> is that mapping (#1186); the PerMonitorV2 switch and
/// per-monitor overlay windows are #1192.
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
    /// Maps a logical selection piecewise: the part on each monitor is clipped to that monitor,
    /// expressed relative to the monitor's logical origin, scaled by the monitor's own scale, and
    /// placed at the monitor's physical origin — so each part is in that monitor's native pixels
    /// whatever the neighbours' scales are. Parts come back in monitor order; monitors the
    /// selection does not touch are omitted. When every monitor is at one scale and each
    /// monitor's physical origin is an exact multiple of that scale (which is how Windows reports
    /// logical origins under system-DPI awareness), this equals <see cref="PhysicalPartOn"/> per
    /// monitor; with a fractional origin × scale the two round in different frames and can differ
    /// by one pixel at the seam.
    /// </summary>
    public static IReadOnlyList<MonitorPart> ToPhysicalPerMonitor(LogicalRect selection, IReadOnlyList<MonitorGeometry> monitors)
    {
        if (monitors.Count == 0)
        {
            throw new ArgumentException("At least one monitor is required.", nameof(monitors));
        }

        var parts = new List<MonitorPart>();
        foreach (var monitor in monitors)
        {
            var bounds = monitor.LogicalBounds;
            var left = Math.Max(selection.X, bounds.X);
            var top = Math.Max(selection.Y, bounds.Y);
            var right = Math.Min(selection.X + selection.Width, bounds.X + bounds.Width);
            var bottom = Math.Min(selection.Y + selection.Height, bounds.Y + bounds.Height);
            if (right <= left || bottom <= top)
            {
                continue;
            }

            // Edges are scaled and rounded relative to the monitor's own origin, so the seam
            // between two monitors lands on each monitor's edge pixel exactly.
            var local = ToPhysical(new LogicalRect(left - bounds.X, top - bounds.Y, right - left, bottom - top), monitor.Scale, monitor.Scale);
            parts.Add(new MonitorPart(
                monitor,
                new PhysicalRect(monitor.PhysicalBounds.X + local.X, monitor.PhysicalBounds.Y + local.Y, local.Width, local.Height)));
        }

        return parts;
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
