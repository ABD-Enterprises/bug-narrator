using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Shell;
using BugNarrator.Windows.Tray;
using BugNarrator.Core.Workflow;
using System.Windows;

namespace BugNarrator.Windows.Shell;

public sealed class WindowsAppShell : IDisposable
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly IWindowsGlobalHotkeyService hotkeyService;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly ISingleInstanceService singleInstanceService;
    private readonly TrayShell trayShell;
    private readonly WindowCoordinator windowCoordinator;

    public WindowsAppShell(
        ISingleInstanceService singleInstanceService,
        WindowsDiagnostics diagnostics,
        IWindowsGlobalHotkeyService hotkeyService,
        IRecordingLifecycleService recordingLifecycleService,
        WindowCoordinator windowCoordinator,
        TrayShell trayShell)
    {
        this.singleInstanceService = singleInstanceService;
        this.diagnostics = diagnostics;
        this.hotkeyService = hotkeyService;
        this.recordingLifecycleService = recordingLifecycleService;
        this.windowCoordinator = windowCoordinator;
        this.trayShell = trayShell;

        recordingLifecycleService.StateChanged += OnRecordingStateChanged;
        trayShell.StartRecordingRequested += OnStartRecordingRequested;
        trayShell.StopRecordingRequested += OnStopRecordingRequested;
        trayShell.CaptureScreenshotRequested += OnCaptureScreenshotRequested;
        trayShell.ToggleRecordingControlsRequested += OnToggleRecordingControlsRequested;
        trayShell.ShowRecordingControlsRequested += OnShowRecordingControlsRequested;
        trayShell.OpenSessionLibraryRequested += OnOpenSessionLibraryRequested;
        trayShell.SettingsRequested += OnSettingsRequested;
        trayShell.AboutRequested += OnAboutRequested;
        trayShell.QuitRequested += OnQuitRequested;
    }

    public bool Initialize()
    {
        diagnostics.Info("app", "app launch");

        if (!singleInstanceService.TryAcquirePrimaryInstance())
        {
            diagnostics.Warning("app", "duplicate instance detected");
            singleInstanceService.SignalPrimaryInstance();
            return false;
        }

        singleInstanceService.StartFocusRequestPump(() =>
        {
            Application.Current.Dispatcher.BeginInvoke(() =>
            {
                diagnostics.Info("app", "focus request received from secondary instance");
                windowCoordinator.FocusPrimarySurface();
            });
        });

        trayShell.Initialize();
        trayShell.ApplyRecordingState(recordingLifecycleService.CurrentState);
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                var snapshot = await hotkeyService.InitializeAsync();
                if (snapshot.HasProblems)
                {
                    trayShell.ShowWarning(
                        "BugNarrator Hotkeys",
                        "Some saved global hotkeys are not active. Open Settings to review them.");
                }
            }
            catch (Exception exception)
            {
                diagnostics.Error("hotkeys", "failed to initialize persisted hotkeys", exception);
            }
        });
        return true;
    }

    public void Dispose()
    {
        recordingLifecycleService.StateChanged -= OnRecordingStateChanged;
        trayShell.StartRecordingRequested -= OnStartRecordingRequested;
        trayShell.StopRecordingRequested -= OnStopRecordingRequested;
        trayShell.CaptureScreenshotRequested -= OnCaptureScreenshotRequested;
        trayShell.ToggleRecordingControlsRequested -= OnToggleRecordingControlsRequested;
        trayShell.ShowRecordingControlsRequested -= OnShowRecordingControlsRequested;
        trayShell.OpenSessionLibraryRequested -= OnOpenSessionLibraryRequested;
        trayShell.SettingsRequested -= OnSettingsRequested;
        trayShell.AboutRequested -= OnAboutRequested;
        trayShell.QuitRequested -= OnQuitRequested;

        windowCoordinator.CloseAll();
        hotkeyService.Dispose();
        trayShell.Dispose();
        recordingLifecycleService.Dispose();
        singleInstanceService.Dispose();
        diagnostics.Info("app", "app exit");
    }

    private void OnCaptureScreenshotRequested(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                var result = await recordingLifecycleService.CaptureScreenshotAsync();
                if (result.Status == ScreenshotCaptureResultStatus.Failed
                    || result.Status == ScreenshotCaptureResultStatus.Unavailable)
                {
                    trayShell.ShowWarning("BugNarrator Screenshot", result.Message);
                }
            }
            catch (Exception exception)
            {
                diagnostics.Error("tray", "capture screenshot request failed", exception);
                trayShell.ShowWarning("BugNarrator Screenshot", exception.Message);
            }
        });
    }

    private void OnAboutRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ShowAbout();
    }

    private void OnOpenSessionLibraryRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ShowSessionLibrary();
    }

    private void OnRecordingStateChanged(object? sender, RecordingControlState state)
    {
        Application.Current.Dispatcher.BeginInvoke(() => trayShell.ApplyRecordingState(state));
    }

    private void OnQuitRequested(object? sender, EventArgs e)
    {
        Application.Current.Shutdown();
    }

    private void OnSettingsRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ShowSettings();
    }

    private void OnStartRecordingRequested(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                await recordingLifecycleService.StartRecordingAsync();
            }
            catch (Exception exception)
            {
                diagnostics.Error("tray", "start recording request failed", exception);
                trayShell.ShowWarning("BugNarrator Recording", exception.Message);
            }
        });
    }

    private void OnStopRecordingRequested(object? sender, EventArgs e)
    {
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                await recordingLifecycleService.StopRecordingAsync();
            }
            catch (Exception exception)
            {
                diagnostics.Error("tray", "stop recording request failed", exception);
                trayShell.ShowWarning("BugNarrator Recording", exception.Message);
            }
        });
    }

    private void OnToggleRecordingControlsRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ToggleRecordingControls();
    }

    private void OnShowRecordingControlsRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ShowRecordingControls();
    }
}
