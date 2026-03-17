using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Views;
using System.Windows;

namespace BugNarrator.Windows.Shell;

public sealed class WindowCoordinator
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private AboutWindow? aboutWindow;
    private RecordingControlsWindow? recordingControlsWindow;
    private SessionLibraryWindow? sessionLibraryWindow;
    private SettingsWindow? settingsWindow;

    public WindowCoordinator(
        WindowsDiagnostics diagnostics,
        IRecordingLifecycleService recordingLifecycleService)
    {
        this.diagnostics = diagnostics;
        this.recordingLifecycleService = recordingLifecycleService;
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
            recordingControlsWindow = new RecordingControlsWindow(recordingLifecycleService, diagnostics);
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
            sessionLibraryWindow = new SessionLibraryWindow();
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
            settingsWindow = new SettingsWindow();
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
