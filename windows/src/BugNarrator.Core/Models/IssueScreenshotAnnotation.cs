using System.Globalization;

namespace BugNarrator.Core.Models;

/// <summary>Annotation style. macOS defines exactly one case today.</summary>
public enum IssueScreenshotAnnotationStyle
{
    Highlight = 0,
}

/// <summary>
/// A normalized highlight region on a session screenshot, mirroring the macOS
/// `IssueScreenshotAnnotation` (Sources/BugNarrator/Models/IssueCoreSubtypes.swift:54).
///
/// Coordinates are normalized 0-1 with a top-left origin. The properties are get-only and clamped in
/// the constructor on purpose: with init-only properties a `with { X = ... }` expression could
/// otherwise produce an out-of-bounds rectangle that never passed through the clamp.
/// </summary>
public sealed class IssueScreenshotAnnotation
{
    /// <summary>Minimum extent macOS allows for a highlight.</summary>
    private const double MinimumExtent = 0.05;

    public IssueScreenshotAnnotation(
        Guid annotationId,
        Guid screenshotId,
        string? label,
        double x,
        double y,
        double width,
        double height,
        double? confidence = null,
        IssueScreenshotAnnotationStyle style = IssueScreenshotAnnotationStyle.Highlight)
    {
        AnnotationId = annotationId;
        ScreenshotId = screenshotId;
        Label = string.IsNullOrWhiteSpace(label) ? null : label.Trim();

        // Same order as the macOS init plus clampRectIntoBounds: size first, then origin bounded so
        // the rectangle cannot extend past the right or bottom edge.
        Width = Clamp(width, MinimumExtent, 1);
        Height = Clamp(height, MinimumExtent, 1);
        X = Clamp(x, 0, Math.Max(0, 1 - Width));
        Y = Clamp(y, 0, Math.Max(0, 1 - Height));

        Confidence = confidence;
        Style = style;
    }

    public Guid AnnotationId { get; }
    public Guid ScreenshotId { get; }
    public string? Label { get; }
    public double X { get; }
    public double Y { get; }
    public double Width { get; }
    public double Height { get; }
    public double? Confidence { get; }
    public IssueScreenshotAnnotationStyle Style { get; }

    /// <summary>Swift `.rounded()` rounds halves away from zero; C# Math.Round defaults to banker's
    /// rounding, which would render 0.845 as 84% where macOS renders 85%.</summary>
    public string? ConfidenceLabel =>
        Confidence is null ? null : $"{Percent(Confidence.Value)}%";

    /// <summary>
    /// The per-annotation text macOS puts in tracker exports: label (or "UI highlight"), the
    /// rectangle as whole percentages, and confidence when known, joined with " • ".
    /// </summary>
    public string ExportDescription
    {
        get
        {
            var parts = new List<string>
            {
                Label ?? "UI highlight",
                $"x {Percent(X)}%",
                $"y {Percent(Y)}%",
                $"w {Percent(Width)}%",
                $"h {Percent(Height)}%",
            };

            if (ConfidenceLabel is { } confidenceLabel)
            {
                parts.Add($"confidence {confidenceLabel}");
            }

            return string.Join(" • ", parts);
        }
    }

    private static int Percent(double value) =>
        (int)Math.Round(value * 100, MidpointRounding.AwayFromZero);

    private static double Clamp(double value, double minimum, double maximum) =>
        double.IsNaN(value) ? minimum : Math.Min(Math.Max(value, minimum), maximum);

    public override string ToString() =>
        ExportDescription.ToString(CultureInfo.InvariantCulture);
}
