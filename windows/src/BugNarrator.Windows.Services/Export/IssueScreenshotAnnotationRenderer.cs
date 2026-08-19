using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Export;

public sealed class IssueScreenshotAnnotationRenderer
{
    private static readonly Color AnnotationFill = Color.FromArgb(41, 250, 84, 54);
    private static readonly Color AnnotationStroke = Color.FromArgb(242, 250, 84, 54);

    public IReadOnlyList<AnnotatedScreenshotExport> AnnotatedScreenshotExports(
        ExtractedIssue issue,
        CompletedSession session)
    {
        var exports = new List<AnnotatedScreenshotExport>();
        var annotationDirectory = string.IsNullOrWhiteSpace(session.SessionDirectory)
            ? null
            : Path.Combine(session.SessionDirectory, "annotated-exports");

        foreach (var screenshot in session.Screenshots
            .Where(item => issue.RelatedScreenshotIds.Contains(item.ScreenshotId))
            .OrderBy(item => item.ElapsedSeconds))
        {
            var annotations = issue.ScreenshotAnnotations
                .Where(annotation => annotation.ScreenshotId == screenshot.ScreenshotId)
                .ToArray();

            if (annotations.Length == 0)
            {
                continue;
            }

            var summaries = string.Join("; ", annotations.Select(annotation => annotation.ExportDescription));
            var renderedFileName = annotationDirectory is null
                ? null
                : TryWriteAnnotatedScreenshot(issue, screenshot, annotations, annotationDirectory);

            exports.Add(new AnnotatedScreenshotExport(
                renderedFileName,
                Path.GetFileName(screenshot.RelativePath),
                SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds),
                summaries));
        }

        return exports;
    }

    private static string? TryWriteAnnotatedScreenshot(
        ExtractedIssue issue,
        ScreenshotArtifact screenshot,
        IReadOnlyList<IssueScreenshotAnnotation> annotations,
        string annotationDirectory)
    {
        if (!File.Exists(screenshot.AbsolutePath))
        {
            return null;
        }

        try
        {
            Directory.CreateDirectory(annotationDirectory);
            var destinationFileName = RenderedFileName(issue, screenshot);
            var destinationPath = Path.Combine(annotationDirectory, destinationFileName);
            RemovePriorRenderedFiles(destinationPath);
            WriteAnnotatedScreenshot(screenshot.AbsolutePath, destinationPath, annotations);
            return destinationFileName;
        }
        catch
        {
            // Export bodies should still be usable when an old/corrupt screenshot cannot be decoded.
            return null;
        }
    }

    private static void WriteAnnotatedScreenshot(
        string sourcePath,
        string destinationPath,
        IReadOnlyList<IssueScreenshotAnnotation> annotations)
    {
        using var source = Image.FromFile(sourcePath);
        using var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppPArgb);
        using var graphics = Graphics.FromImage(output);

        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.DrawImage(source, 0, 0, source.Width, source.Height);

        using var fill = new SolidBrush(AnnotationFill);
        using var stroke = new Pen(AnnotationStroke);

        foreach (var annotation in annotations)
        {
            var rect = new RectangleF(
                (float)(annotation.X * source.Width),
                (float)(annotation.Y * source.Height),
                (float)(annotation.Width * source.Width),
                (float)(annotation.Height * source.Height));
            stroke.Width = MathF.Max(4, MathF.Min(rect.Width, rect.Height) * 0.04f);

            graphics.FillRectangle(fill, rect);
            graphics.DrawRectangle(stroke, rect.X, rect.Y, rect.Width, rect.Height);

            var arrowLength = MathF.Max(18, MathF.Min(source.Width, source.Height) * 0.05f);
            var anchor = new PointF(rect.Left, rect.Top);
            graphics.DrawLines(
                stroke,
                [
                    new PointF(anchor.X - arrowLength, anchor.Y - arrowLength),
                    anchor,
                    new PointF(anchor.X + arrowLength * 0.45f, anchor.Y - arrowLength),
                ]);
        }

        output.Save(destinationPath, ImageFormat.Png);
    }

    private static string RenderedFileName(ExtractedIssue issue, ScreenshotArtifact screenshot)
    {
        var sourceName = Path.GetFileNameWithoutExtension(screenshot.RelativePath);
        var issuePrefix = issue.IssueId.ToString("D").Split('-')[0];
        return $"{sourceName}-annotated-{issuePrefix}.png";
    }

    private static void RemovePriorRenderedFiles(string destinationPath)
    {
        if (File.Exists(destinationPath))
        {
            File.Delete(destinationPath);
        }
    }
}

public sealed record AnnotatedScreenshotExport(
    string? RenderedFileName,
    string ScreenshotFileName,
    string TimeLabel,
    string Summaries);
