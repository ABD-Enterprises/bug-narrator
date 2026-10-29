using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Views;

public sealed class IssueScreenshotAnnotationEditor : StackPanel
{
    private readonly List<IssueScreenshotAnnotation> annotations;
    private readonly Canvas overlay = new() { ClipToBounds = true };
    private readonly Grid preview = new() { Height = 220, ClipToBounds = true };
    private readonly StackPanel descriptions = new();
    private readonly string fileName;
    private BitmapSource? bitmap;

    public IssueScreenshotAnnotationEditor(ScreenshotArtifact screenshot, IEnumerable<IssueScreenshotAnnotation> annotations)
    {
        ScreenshotId = screenshot.ScreenshotId;
        this.annotations = annotations.Where(item => item.ScreenshotId == ScreenshotId).ToList();
        fileName = Path.GetFileName(screenshot.RelativePath);
        Margin = new Thickness(0, 0, 0, 12);
        Children.Add(new TextBlock
        {
            Text = $"{fileName} ({SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)})",
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap,
        });

        try
        {
            using var stream = File.OpenRead(screenshot.AbsolutePath);
            var image = new BitmapImage();
            image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 960;
            image.StreamSource = stream;
            image.EndInit();
            image.Freeze();
            bitmap = image;
            preview.Children.Add(new Image { Source = bitmap, Stretch = Stretch.Uniform });
            preview.Children.Add(overlay);
            AutomationProperties.SetName(preview, $"Annotated screenshot preview for {fileName}");
            preview.SizeChanged += (_, _) => RenderOverlays();
            Children.Add(preview);
            Children.Add(new TextBlock
            {
                Text = "Drag a highlight to reposition it, or focus it and use the arrow keys. Hold Shift for larger steps.",
                TextWrapping = TextWrapping.Wrap,
                Foreground = Brushes.DimGray,
            });
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException
            or NotSupportedException or System.IO.FileFormatException or ArgumentException)
        {
            Children.Add(new TextBlock
            {
                Text = $"Annotated preview unavailable for {fileName}. Highlights can still be removed below.",
                TextWrapping = TextWrapping.Wrap,
            });
        }

        Children.Add(descriptions);
        RenderDescriptions();
    }

    public Guid ScreenshotId { get; }
    public IReadOnlyList<IssueScreenshotAnnotation> Annotations => annotations.ToArray();

    internal Rect ImageFrame
    {
        get
        {
            if (bitmap is null || bitmap.Width <= 0 || bitmap.Height <= 0)
            {
                return Rect.Empty;
            }
            var scale = Math.Min(preview.ActualWidth / bitmap.Width, preview.ActualHeight / bitmap.Height);
            var width = bitmap.Width * scale;
            var height = bitmap.Height * scale;
            return new Rect((preview.ActualWidth - width) / 2, (preview.ActualHeight - height) / 2, width, height);
        }
    }

    internal void RenderOverlays()
    {
        overlay.Children.Clear();
        var frame = ImageFrame;
        if (frame.IsEmpty || frame.Width <= 0 || frame.Height <= 0)
        {
            return;
        }

        foreach (var annotation in annotations)
        {
            var highlight = new Thumb
            {
                Width = frame.Width * annotation.Width,
                Height = frame.Height * annotation.Height,
                Focusable = true,
                IsTabStop = true,
                Cursor = Cursors.SizeAll,
                ToolTip = annotation.Label ?? "UI highlight",
            };
            var border = new FrameworkElementFactory(typeof(Border));
            border.SetValue(Border.BackgroundProperty, new SolidColorBrush(Color.FromArgb(40, 250, 84, 54)));
            border.SetValue(Border.BorderBrushProperty, Brushes.OrangeRed);
            border.SetValue(Border.BorderThicknessProperty, new Thickness(2));
            highlight.Template = new ControlTemplate(typeof(Thumb)) { VisualTree = border };
            AutomationProperties.SetName(highlight, $"{annotation.Label ?? "UI highlight"} in {fileName}");
            AutomationProperties.SetHelpText(highlight, "Drag or use arrow keys to reposition the highlight.");
            PositionHighlight(highlight, annotation, frame);
            highlight.DragDelta += (_, args) =>
            {
                MoveAnnotationPixels(annotation.AnnotationId, args.HorizontalChange, args.VerticalChange);
                PositionHighlight(highlight, annotations.First(item => item.AnnotationId == annotation.AnnotationId), ImageFrame);
            };
            highlight.PreviewKeyDown += (_, args) =>
            {
                if (MoveWithKey(annotation.AnnotationId, args.Key, Keyboard.Modifiers))
                {
                    PositionHighlight(highlight, annotations.First(item => item.AnnotationId == annotation.AnnotationId), ImageFrame);
                    args.Handled = true;
                }
            };
            overlay.Children.Add(highlight);
        }
    }

    private static void PositionHighlight(Thumb highlight, IssueScreenshotAnnotation annotation, Rect frame)
    {
        Canvas.SetLeft(highlight, frame.X + annotation.X * frame.Width);
        Canvas.SetTop(highlight, frame.Y + annotation.Y * frame.Height);
    }

    internal void MoveAnnotationPixels(Guid annotationId, double deltaX, double deltaY)
    {
        var frame = ImageFrame;
        var index = annotations.FindIndex(item => item.AnnotationId == annotationId);
        if (index < 0 || frame.IsEmpty || frame.Width <= 0 || frame.Height <= 0)
        {
            return;
        }
        annotations[index] = annotations[index].MovedBy(deltaX / frame.Width, deltaY / frame.Height);
        RenderDescriptions();
    }

    internal bool MoveWithKey(Guid annotationId, Key key, ModifierKeys modifiers)
    {
        var distance = modifiers.HasFlag(ModifierKeys.Shift) ? 10 : 1;
        var delta = key switch
        {
            Key.Left => new Vector(-distance, 0),
            Key.Right => new Vector(distance, 0),
            Key.Up => new Vector(0, -distance),
            Key.Down => new Vector(0, distance),
            _ => new Vector(),
        };
        if (delta.LengthSquared == 0)
        {
            return false;
        }
        MoveAnnotationPixels(annotationId, delta.X, delta.Y);
        return true;
    }

    private void RenderDescriptions()
    {
        descriptions.Children.Clear();
        foreach (var annotation in annotations)
        {
            var remove = new Button { Content = "Remove highlight", Margin = new Thickness(0, 4, 0, 8) };
            AutomationProperties.SetName(remove, $"Remove annotation {annotation.Label ?? "highlight"} from {fileName}");
            remove.Click += (_, _) =>
            {
                annotations.RemoveAll(item => item.AnnotationId == annotation.AnnotationId);
                RenderDescriptions();
                RenderOverlays();
            };
            descriptions.Children.Add(new TextBlock { Text = annotation.ExportDescription, TextWrapping = TextWrapping.Wrap });
            descriptions.Children.Add(remove);
        }
        if (annotations.Count == 0)
        {
            descriptions.Children.Add(new TextBlock { Text = "No highlights remain on this screenshot." });
        }
    }
}
