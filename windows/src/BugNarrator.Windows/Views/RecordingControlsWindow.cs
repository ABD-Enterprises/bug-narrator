using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using System.Windows;
using System.Windows.Controls;

namespace BugNarrator.Windows.Views;

public sealed class RecordingControlsWindow : Window
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly Button startButton;
    private readonly Button stopButton;
    private readonly Button screenshotButton;
    private readonly TextBlock stateTextBlock;
    private readonly TextBlock statusTextBlock;

    public RecordingControlsWindow(
        IRecordingLifecycleService recordingLifecycleService,
        WindowsDiagnostics diagnostics)
    {
        this.recordingLifecycleService = recordingLifecycleService;
        this.diagnostics = diagnostics;

        Title = "BugNarrator Controls";
        Width = 420;
        Height = 340;
        MinWidth = 360;
        MinHeight = 300;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        startButton = new Button
        {
            Content = "Start Recording",
            Height = 38,
            Margin = new Thickness(0, 0, 0, 10),
        };
        startButton.Click += OnStartRecordingClicked;

        stopButton = new Button
        {
            Content = "Stop Recording",
            Height = 38,
            Margin = new Thickness(0, 0, 0, 10),
        };
        stopButton.Click += OnStopRecordingClicked;

        screenshotButton = new Button
        {
            Content = "Capture Screenshot",
            Height = 38,
            Margin = new Thickness(0, 0, 0, 14),
            IsEnabled = false,
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

        var closeButton = new Button
        {
            Content = "Close",
            Height = 34,
            Margin = new Thickness(0, 18, 0, 0),
        };
        closeButton.Click += (_, _) => Close();

        Content = new Border
        {
            Padding = new Thickness(24),
            Child = new StackPanel
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
                        Margin = new Thickness(0, 12, 0, 0),
                        Text = "Milestone 4 adds drag-select screenshot capture, screenshot metadata, and screenshot-linked timeline moments while keeping recording stable.",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new TextBlock
                    {
                        Margin = new Thickness(0, 16, 0, 0),
                        Foreground = System.Windows.Media.Brushes.DimGray,
                        Text = "Source-of-truth docs: windows/docs/WINDOWS_IMPLEMENTATION_ROADMAP.md and docs/CROSS_PLATFORM_GUIDELINES.md",
                        TextWrapping = TextWrapping.Wrap,
                    },
                    new Border
                    {
                        Margin = new Thickness(0, 18, 0, 18),
                        Padding = new Thickness(12),
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
                    },
                    startButton,
                    stopButton,
                    screenshotButton,
                    closeButton,
                },
            },
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
