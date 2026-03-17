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

    private Point dragStartPoint;
    private bool isDragging;

    public ScreenshotSelectionOverlayWindow()
    {
        Left = SystemParameters.VirtualScreenLeft;
        Top = SystemParameters.VirtualScreenTop;
        Width = SystemParameters.VirtualScreenWidth;
        Height = SystemParameters.VirtualScreenHeight;
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

        var currentPoint = eventArgs.GetPosition(canvas);
        var left = Math.Min(dragStartPoint.X, currentPoint.X);
        var top = Math.Min(dragStartPoint.Y, currentPoint.Y);
        var width = Math.Abs(currentPoint.X - dragStartPoint.X);
        var height = Math.Abs(currentPoint.Y - dragStartPoint.Y);

        if (width < MinimumSelectionSize || height < MinimumSelectionSize)
        {
            CancelSelection();
            return;
        }

        SelectionResult = new ScreenshotSelectionResult(
            ScreenshotSelectionStatus.Selected,
            new ScreenshotSelection(
                X: (int)Math.Round(Left + left),
                Y: (int)Math.Round(Top + top),
                Width: (int)Math.Round(width),
                Height: (int)Math.Round(height)));

        Close();
    }
}
