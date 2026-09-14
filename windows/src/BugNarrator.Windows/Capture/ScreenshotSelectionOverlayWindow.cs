using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Capture;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;

namespace BugNarrator.Windows.Capture;

internal sealed class ScreenshotSelectionOverlayWindow : Window
{
    private const double MinimumSelectionSize = 6;

    private readonly Canvas canvas;
    private readonly TextBlock hintText;
    private readonly Rectangle selectionRectangle;

    private readonly Func<(double X, double Y)> deviceScale;

    private Point dragStartPoint;
    private bool isDragging;

    public ScreenshotSelectionOverlayWindow()
        : this(deviceScale: null, virtualScreen: null)
    {
    }

    /// <summary>
    /// <paramref name="deviceScale"/> overrides the window's own DIP → device transform and
    /// <paramref name="virtualScreen"/> the SystemParameters virtual-screen bounds; tests use them
    /// to emulate a 125 % or 150 % display and a multi-monitor desktop without real hardware.
    /// </summary>
    internal ScreenshotSelectionOverlayWindow(Func<(double X, double Y)>? deviceScale, LogicalRect? virtualScreen)
    {
        this.deviceScale = deviceScale ?? DeviceScaleFromPresentationSource;
        // The overlay spans every monitor at once: the virtual screen, in DIPs.
        var bounds = virtualScreen ?? new LogicalRect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            SystemParameters.VirtualScreenWidth,
            SystemParameters.VirtualScreenHeight);
        Left = bounds.X;
        Top = bounds.Y;
        Width = bounds.Width;
        Height = bounds.Height;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Cursor = Cursors.Cross;
        Focusable = true;

        selectionRectangle = new Rectangle
        {
            Stroke = Brushes.White,
            StrokeThickness = 2,
            Fill = new SolidColorBrush(Color.FromArgb(50, 255, 255, 255)),
            Visibility = Visibility.Collapsed,
        };

        hintText = new TextBlock
        {
            Margin = new Thickness(20),
            Padding = new Thickness(10, 6, 10, 6),
            Background = new SolidColorBrush(Color.FromArgb(175, 20, 20, 20)),
            Foreground = Brushes.White,
            Text = "Drag to capture a region • Esc to cancel",
        };

        canvas = new Canvas
        {
            Background = new SolidColorBrush(Color.FromArgb(100, 0, 0, 0)),
        };
        canvas.Children.Add(selectionRectangle);
        canvas.Children.Add(hintText);

        Content = canvas;

        Loaded += (_, _) =>
        {
            Activate();
            Focus();
            Keyboard.Focus(this);
        };

        MouseLeftButtonDown += OnMouseLeftButtonDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        KeyDown += OnKeyDown;

        SelectionResult = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Cancelled,
            Selection: null);
    }

    public ScreenshotSelectionResult SelectionResult { get; private set; }

    public void CancelSelection()
    {
        SelectionResult = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Cancelled,
            Selection: null);

        if (IsVisible)
        {
            Close();
        }
    }

    private void OnKeyDown(object sender, KeyEventArgs eventArgs)
    {
        if (eventArgs.Key == Key.Escape)
        {
            CancelSelection();
        }
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs eventArgs)
    {
        dragStartPoint = eventArgs.GetPosition(canvas);
        isDragging = true;
        selectionRectangle.Visibility = Visibility.Visible;
        Canvas.SetLeft(selectionRectangle, dragStartPoint.X);
        Canvas.SetTop(selectionRectangle, dragStartPoint.Y);
        selectionRectangle.Width = 0;
        selectionRectangle.Height = 0;
        Mouse.Capture(this);
    }

    private void OnMouseMove(object sender, MouseEventArgs eventArgs)
    {
        if (!isDragging)
        {
            return;
        }

        var currentPoint = eventArgs.GetPosition(canvas);
        var left = Math.Min(dragStartPoint.X, currentPoint.X);
        var top = Math.Min(dragStartPoint.Y, currentPoint.Y);
        var width = Math.Abs(currentPoint.X - dragStartPoint.X);
        var height = Math.Abs(currentPoint.Y - dragStartPoint.Y);

        Canvas.SetLeft(selectionRectangle, left);
        Canvas.SetTop(selectionRectangle, top);
        selectionRectangle.Width = width;
        selectionRectangle.Height = height;
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs eventArgs)
    {
        if (!isDragging)
        {
            return;
        }

        isDragging = false;
        Mouse.Capture(null);

        CompleteDrag(dragStartPoint, eventArgs.GetPosition(canvas));
    }

    /// <summary>
    /// The production path from a finished drag (canvas DIPs) to the physical-pixel selection the
    /// capture service uses; internal so the DPI tests can drive it without synthesizing mouse input.
    /// </summary>
    internal void CompleteDrag(Point start, Point end)
    {
        var left = Math.Min(start.X, end.X);
        var top = Math.Min(start.Y, end.Y);
        var width = Math.Abs(end.X - start.X);
        var height = Math.Abs(end.Y - start.Y);

        if (width < MinimumSelectionSize || height < MinimumSelectionSize)
        {
            CancelSelection();
            return;
        }

        // The drag is measured in DIPs; CopyFromScreen and the PNG are physical pixels (#1134).
        var scale = deviceScale();
        var physical = ScreenshotCaptureGeometry.ToPhysical(
            new LogicalRect(Left + left, Top + top, width, height),
            scale.X,
            scale.Y);
        SelectionResult = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Selected,
            new ScreenshotSelection(physical.X, physical.Y, physical.Width, physical.Height));

        Close();
    }

    /// <summary>DIP → device pixel factors for this window; 1.0 before the window has a presentation source.</summary>
    private (double X, double Y) DeviceScaleFromPresentationSource()
    {
        var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice;
        return transform is { } matrix ? (matrix.M11, matrix.M22) : (1.0, 1.0);
    }
}
