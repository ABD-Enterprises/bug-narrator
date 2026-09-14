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
    private readonly IExternalLinkLauncher externalLinkLauncher;
    private readonly ReleaseUpdateChecker releaseUpdateChecker;
    private bool isCheckingForUpdates;
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
        TrayShell trayShell,
        IExternalLinkLauncher externalLinkLauncher,
        ReleaseUpdateChecker? releaseUpdateChecker = null)
    {
        this.releaseUpdateChecker = releaseUpdateChecker ?? new ReleaseUpdateChecker();
        this.singleInstanceService = singleInstanceService;
        this.diagnostics = diagnostics;
        this.externalLinkLauncher = externalLinkLauncher;
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
        trayShell.OpenLinkRequested += OnOpenLinkRequested;
        trayShell.SampleSessionRequested += OnSampleSessionRequested;
        trayShell.WelcomeTourRequested += OnWelcomeTourRequested;
        trayShell.RecoveryRequested += OnRecoveryRequested;
        trayShell.CheckForUpdatesRequested += OnCheckForUpdatesRequested;
        // Re-evaluated whenever the menu opens: deleting the last session in the library does not
        // notify the shell, so a startup-only read would go stale.
        trayShell.MenuOpening += OnTrayMenuOpening;
        _ = RefreshSampleSessionOfferAsync();
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

            await PresentWelcomeIfNeededAsync();
        });
        return true;
    }

    /// <summary>
    /// The one window a launch may open unprompted (#1167). Presented once per the FirstRunFunnel
    /// rule; the window itself makes dismissal durable, so a second launch never re-prompts.
    /// </summary>
    private async Task PresentWelcomeIfNeededAsync()
    {
        try
        {
            if (await windowCoordinator.ShouldPresentWelcomeAsync())
            {
                diagnostics.Info("app", "presenting first-run welcome tour");
                await windowCoordinator.ShowWelcomeAtLaunchAsync();
            }
        }
        catch (Exception exception)
        {
            diagnostics.Error("app", "failed to evaluate the first-run welcome rule", exception);
        }
    }

    /// <summary>
    /// macOS Check for Updates (#961): run the check, show the outcome on the status line, and open
    /// only what the outcome says — that release, the releases page after a failed check, nothing
    /// when up to date. The status line is restored by the next recording-state update.
    /// </summary>
    private void OnCheckForUpdatesRequested(object? sender, EventArgs e)
    {
        if (isCheckingForUpdates)
        {
            return;
        }

        isCheckingForUpdates = true;
        trayShell.ShowStatus("Status: Checking for updates...");
        Application.Current.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                var outcome = await releaseUpdateChecker.CheckAsync(ReleaseUpdateChecker.CurrentVersion());
                diagnostics.Info("updates", $"release check: {outcome.Kind}");
                trayShell.ShowStatus(outcome.UserMessage);
                if (outcome.UrlToOpen(BugNarratorLinks.Releases) is { } url)
                {
                    OnOpenLinkRequested(this, url);
                }
            }
            catch (Exception exception)
            {
                diagnostics.Error("updates", "release check failed unexpectedly", exception);
                trayShell.ShowStatus($"BugNarrator could not check for updates: {exception.Message}");
            }
            finally
            {
                isCheckingForUpdates = false;
            }
        });
    }

    private void OnRecoveryRequested(object? sender, RecoveryDestination destination)
    {
        diagnostics.Info("app", $"recovery entry chosen: {destination}");
        switch (destination)
        {
            case RecoveryDestination.Settings:
                windowCoordinator.ShowSettings();
                break;
            case RecoveryDestination.RecordingControls:
                windowCoordinator.ShowRecordingControls();
                break;
            case RecoveryDestination.SessionLibrary:
                windowCoordinator.ShowSessionLibrary();
                break;
        }
    }

    private void OnWelcomeTourRequested(object? sender, EventArgs e)
    {
        windowCoordinator.ShowWelcome();
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
        trayShell.OpenLinkRequested -= OnOpenLinkRequested;
        trayShell.SampleSessionRequested -= OnSampleSessionRequested;
        trayShell.WelcomeTourRequested -= OnWelcomeTourRequested;
        trayShell.RecoveryRequested -= OnRecoveryRequested;
        trayShell.CheckForUpdatesRequested -= OnCheckForUpdatesRequested;
        trayShell.MenuOpening -= OnTrayMenuOpening;
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

    private void OnTrayMenuOpening(object? sender, EventArgs e)
    {
        _ = RefreshSampleSessionOfferAsync();
    }

    private async void OnSampleSessionRequested(object? sender, EventArgs e)
    {
        try
        {
            await windowCoordinator.AddSampleSessionAndShowLibraryAsync();
            await RefreshSampleSessionOfferAsync();
        }
        catch (Exception exception)
        {
            diagnostics.Error("tray", "adding the sample session failed", exception);
            trayShell.ShowStatus("Status: Could not add the sample session. See the log for details.");
        }
    }

    private async Task RefreshSampleSessionOfferAsync()
    {
        try
        {
            var count = await windowCoordinator.CountSessionsAsync();
            trayShell.SetSampleSessionOfferVisible(TrayPresentationState.ShouldOfferSampleSession(count));
        }
        catch (Exception exception)
        {
            diagnostics.Warning("tray", $"sample session offer refresh failed: {exception.Message}");
        }
    }

    private void OnOpenLinkRequested(object? sender, string url)
    {
        try
        {
            externalLinkLauncher.Open(url);
            diagnostics.Info("tray", $"opened external link {url}");
        }
        catch (Exception exception)
        {
            // Not swallowed: the log has the cause and the tray status line tells the user, the same
            // way the macOS utility-action presenter reports a failed open.
            diagnostics.Error("tray", $"failed to open external link {url}", exception);
            trayShell.ShowStatus("Status: Could not open the link. See the log for details.");
        }
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
        if (state.WorkflowState == RecordingWorkflowState.Completed)
        {
            // The library just gained a real session; the sample offer is noise from here on.
            Application.Current.Dispatcher.BeginInvoke(() => _ = RefreshSampleSessionOfferAsync());
        }
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
