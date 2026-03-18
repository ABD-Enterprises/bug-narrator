using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Views;
using System.Windows;

namespace BugNarrator.Windows.Shell;

public sealed class WindowCoordinator
{
    private readonly ICompletedSessionStore completedSessionStore;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly IReviewSessionActionService reviewSessionActionService;
    private readonly ISecretStore secretStore;
    private readonly IWindowsGlobalHotkeyService hotkeyService;
    private readonly IWindowsAppSettingsStore settingsStore;
    private readonly ITranscriptionClient transcriptionClient;
    private AboutWindow? aboutWindow;
    private RecordingWorkflowState lastObservedWorkflowState;
    private RecordingControlsWindow? recordingControlsWindow;
    private SessionLibraryWindow? sessionLibraryWindow;
    private SettingsWindow? settingsWindow;

    public WindowCoordinator(
        WindowsDiagnostics diagnostics,
        IRecordingLifecycleService recordingLifecycleService,
        ICompletedSessionStore completedSessionStore,
        IReviewSessionActionService reviewSessionActionService,
        IWindowsAppSettingsStore settingsStore,
        IWindowsGlobalHotkeyService hotkeyService,
        ISecretStore secretStore,
        ITranscriptionClient transcriptionClient)
    {
        this.diagnostics = diagnostics;
        this.recordingLifecycleService = recordingLifecycleService;
        this.completedSessionStore = completedSessionStore;
        this.reviewSessionActionService = reviewSessionActionService;
        this.settingsStore = settingsStore;
        this.hotkeyService = hotkeyService;
        this.secretStore = secretStore;
        this.transcriptionClient = transcriptionClient;

        lastObservedWorkflowState = recordingLifecycleService.CurrentState.WorkflowState;
        recordingLifecycleService.StateChanged += OnRecordingStateChanged;
    }

    public void CloseAll()
    {
        CloseWindow(recordingControlsWindow);
        CloseWindow(sessionLibraryWindow);
        CloseWindow(settingsWindow);
        CloseWindow(aboutWindow);
    }

    public void FocusPrimarySurface()
    {
        if (TryFocusExistingWindow())
        {
            diagnostics.Info("windows", "focused existing window after duplicate-launch request");
            return;
        }

        ShowRecordingControls();
    }

    public void ShowAbout()
    {
        if (aboutWindow is null || !aboutWindow.IsLoaded)
        {
            aboutWindow = new AboutWindow();
            aboutWindow.Closed += (_, _) =>
            {
                diagnostics.Info("windows", "about window closed");
                aboutWindow = null;
            };
            diagnostics.Info("windows", "about window created");
        }

        ShowAndActivate(aboutWindow);
    }

    public void ShowRecordingControls()
    {
        if (recordingControlsWindow is null || !recordingControlsWindow.IsLoaded)
        {
            recordingControlsWindow = new RecordingControlsWindow(
                recordingLifecycleService,
                diagnostics,
                ShowSessionLibrary);
            recordingControlsWindow.Closed += (_, _) =>
            {
                diagnostics.Info("windows", "recording controls window closed");
                recordingControlsWindow = null;
            };
            diagnostics.Info("windows", "recording controls window created");
        }

        ShowAndActivate(recordingControlsWindow);
    }

    public void ShowSessionLibrary()
    {
        if (sessionLibraryWindow is null || !sessionLibraryWindow.IsLoaded)
        {
            sessionLibraryWindow = new SessionLibraryWindow(
                completedSessionStore,
                reviewSessionActionService,
                diagnostics);
            sessionLibraryWindow.Closed += (_, _) =>
            {
                diagnostics.Info("windows", "session library window closed");
                sessionLibraryWindow = null;
            };
            diagnostics.Info("windows", "session library window created");
        }

        ShowAndActivate(sessionLibraryWindow);
    }

    public void ShowSettings()
    {
        if (settingsWindow is null || !settingsWindow.IsLoaded)
        {
            settingsWindow = new SettingsWindow(
                settingsStore,
                secretStore,
                transcriptionClient,
                hotkeyService,
                diagnostics);
            settingsWindow.Closed += (_, _) =>
            {
                diagnostics.Info("windows", "settings window closed");
                settingsWindow = null;
            };
            diagnostics.Info("windows", "settings window created");
        }

        ShowAndActivate(settingsWindow);
    }

    private static void CloseWindow(Window? window)
    {
        if (window is { IsLoaded: true })
        {
            window.Close();
        }
    }

    private static void ShowAndActivate(Window window)
    {
        if (!window.IsVisible)
        {
            window.Show();
        }

        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.Activate();
        window.Topmost = true;
        window.Topmost = false;
        window.Focus();
    }

    private void OnRecordingStateChanged(object? sender, RecordingControlState state)
    {
        var shouldFocusSessionLibrary = state.WorkflowState == RecordingWorkflowState.Completed
                                        && lastObservedWorkflowState != RecordingWorkflowState.Completed;
        lastObservedWorkflowState = state.WorkflowState;

        if (!shouldFocusSessionLibrary)
        {
            return;
        }

        Application.Current.Dispatcher.BeginInvoke(() =>
        {
            diagnostics.Info("windows", "recording completed, focusing session library");
            ShowSessionLibrary();
        });
    }

    private bool TryFocusExistingWindow()
    {
        foreach (var window in new Window?[]
                 {
                     recordingControlsWindow,
                     sessionLibraryWindow,
                     settingsWindow,
                     aboutWindow,
                 })
        {
            if (window is { IsLoaded: true })
            {
                ShowAndActivate(window);
                return true;
            }
        }

        return false;
    }
}
