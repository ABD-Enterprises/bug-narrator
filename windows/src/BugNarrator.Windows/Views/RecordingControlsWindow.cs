using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace BugNarrator.Windows.Views;

public sealed class RecordingControlsWindow : Window
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly Action openSessionLibrary;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly Button startButton;
    private readonly Button stopButton;
    private readonly Button screenshotButton;
    private readonly TextBlock stateTextBlock;
    private readonly TextBlock statusTextBlock;

    public RecordingControlsWindow(
        IRecordingLifecycleService recordingLifecycleService,
        WindowsDiagnostics diagnostics,
        Action openSessionLibrary)
    {
        this.recordingLifecycleService = recordingLifecycleService;
        this.diagnostics = diagnostics;
        this.openSessionLibrary = openSessionLibrary;

        Title = "BugNarrator Controls";
        Width = 460;
        MinWidth = 420;
        MinHeight = 300;
        MaxHeight = SystemParameters.WorkArea.Height - 40;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        startButton = new Button
        {
            Content = "Start Recording",
            Height = 38,
            Margin = new Thickness(0, 0, 6, 0),
        };
        startButton.Click += OnStartRecordingClicked;

        stopButton = new Button
        {
            Content = "Stop Recording",
            Height = 38,
            Margin = new Thickness(6, 0, 0, 0),
        };
        stopButton.Click += OnStopRecordingClicked;

        screenshotButton = new Button
        {
            Content = "Capture Screenshot",
            Height = 38,
            Margin = new Thickness(0, 0, 6, 0),
            IsEnabled = false,
            ToolTip = "Available while a recording is active.",
        };
        screenshotButton.Click += OnCaptureScreenshotClicked;

        stateTextBlock = new TextBlock
        {
            FontWeight = FontWeights.SemiBold,
        };

        statusTextBlock = new TextBlock
        {
            Margin = new Thickness(0, 8, 0, 0),
            TextWrapping = TextWrapping.Wrap,
        };

        var openLibraryButton = new Button
        {
            Content = "Open Session Library",
            Height = 38,
            Margin = new Thickness(6, 0, 0, 0),
        };
        openLibraryButton.Click += OnOpenSessionLibraryClicked;

        var contentGrid = new Grid
        {
            RowDefinitions =
            {
                new RowDefinition
                {
                    Height = GridLength.Auto,
                },
                new RowDefinition
                {
                    Height = GridLength.Auto,
                },
                new RowDefinition
                {
                    Height = GridLength.Auto,
                },
                new RowDefinition
                {
                    Height = GridLength.Auto,
                },
            },
        };

        var headerPanel = new StackPanel
        {
            Children =
            {
                new TextBlock
                {
                    FontSize = 28,
                    FontWeight = FontWeights.Bold,
                    Text = "Recording Controls",
                },
                new TextBlock
                {
                    Margin = new Thickness(0, 8, 0, 0),
                    Foreground = System.Windows.Media.Brushes.DimGray,
                    Text = "Live capture happens here. Use Session Library for review and export.",
                    TextWrapping = TextWrapping.Wrap,
                },
            },
        };

        var statusPanel = new Border
        {
            Margin = new Thickness(0, 16, 0, 0),
            Padding = new Thickness(12, 10, 12, 10),
            BorderThickness = new Thickness(1),
            BorderBrush = System.Windows.Media.Brushes.LightGray,
            CornerRadius = new CornerRadius(8),
            Child = new StackPanel
            {
                Children =
                {
                    stateTextBlock,
                    statusTextBlock,
                },
            },
        };

        var actionGrid = new Grid
        {
            Margin = new Thickness(0, 16, 0, 0),
            ColumnDefinitions =
            {
                new ColumnDefinition(),
                new ColumnDefinition(),
            },
        };
        Grid.SetColumn(startButton, 0);
        Grid.SetColumn(stopButton, 1);
        actionGrid.Children.Add(startButton);
        actionGrid.Children.Add(stopButton);

        var secondaryActionGrid = new Grid
        {
            Margin = new Thickness(0, 8, 0, 0),
            ColumnDefinitions =
            {
                new ColumnDefinition(),
                new ColumnDefinition(),
            },
        };
        Grid.SetColumn(screenshotButton, 0);
        Grid.SetColumn(openLibraryButton, 1);
        secondaryActionGrid.Children.Add(screenshotButton);
        secondaryActionGrid.Children.Add(openLibraryButton);

        Grid.SetRow(headerPanel, 0);
        Grid.SetRow(statusPanel, 1);
        Grid.SetRow(actionGrid, 2);
        Grid.SetRow(secondaryActionGrid, 3);
        contentGrid.Children.Add(headerPanel);
        contentGrid.Children.Add(statusPanel);
        contentGrid.Children.Add(actionGrid);
        contentGrid.Children.Add(secondaryActionGrid);

        Content = new Border
        {
            Padding = new Thickness(24),
            Child = contentGrid,
        };

        recordingLifecycleService.StateChanged += OnStateChanged;
        Closed += OnClosed;
        ApplyState(recordingLifecycleService.CurrentState);
    }

    private void ApplyState(RecordingControlState state)
    {
        stateTextBlock.Text = $"State: {state.WorkflowState}";
        statusTextBlock.Text = state.StatusMessage;
        startButton.IsEnabled = state.CanStart;
        stopButton.IsEnabled = state.CanStop;
        screenshotButton.IsEnabled = state.CanCaptureScreenshot;
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        recordingLifecycleService.StateChanged -= OnStateChanged;
    }

    private async void OnStartRecordingClicked(object? sender, RoutedEventArgs e)
    {
        try
        {
            await recordingLifecycleService.StartRecordingAsync();
        }
        catch (Exception exception)
        {
            diagnostics.Error("ui", "recording start click failed", exception);
        }
    }

    private void OnStateChanged(object? sender, RecordingControlState state)
    {
        Dispatcher.Invoke(() => ApplyState(state));
    }

    private void OnOpenSessionLibraryClicked(object? sender, RoutedEventArgs e)
    {
        try
        {
            openSessionLibrary();
        }
        catch (Exception exception)
        {
            diagnostics.Error("ui", "open session library click failed", exception);
        }
    }

    private async void OnStopRecordingClicked(object? sender, RoutedEventArgs e)
    {
        try
        {
            await recordingLifecycleService.StopRecordingAsync();
        }
        catch (Exception exception)
        {
            diagnostics.Error("ui", "recording stop click failed", exception);
        }
    }

    private async void OnCaptureScreenshotClicked(object? sender, RoutedEventArgs e)
    {
        try
        {
            await recordingLifecycleService.CaptureScreenshotAsync();
        }
        catch (Exception exception)
        {
            diagnostics.Error("ui", "capture screenshot click failed", exception);
        }
    }
}
