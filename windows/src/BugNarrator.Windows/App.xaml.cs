using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Capture;
using System.Windows.Threading;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Shell;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Shell;
using BugNarrator.Windows.Tray;
using BugNarrator.Windows.Capture;
using System.Windows;

namespace BugNarrator.Windows;

public partial class App : Application
{
    private WindowsAppShell? appShell;
    private WindowsDiagnostics? diagnostics;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += OnDispatcherUnhandledException;

        var storagePaths = AppStoragePathProvider.CreateDefault();
        diagnostics = new WindowsDiagnostics(storagePaths);
        diagnostics.Info("app", "starting Windows shell bootstrap");

        var singleInstanceService = new SingleInstanceService("ABDEnterprises.BugNarrator.Windows");
        var microphonePreflightService = new MicrophonePreflightService();
        var screenCapturePreflightService = new ScreenCapturePreflightService();
        var audioRecorderService = new NAudioRecorderService();
        var screenshotSelectionOverlayService = new WpfScreenshotSelectionOverlayService();
        var screenshotImageCaptureService = new DesktopScreenshotImageCaptureService();
        var sessionDraftStore = new FileSessionDraftStore(storagePaths);
        var recordingLifecycleService = new RecordingLifecycleService(
            audioRecorderService,
            microphonePreflightService,
            sessionDraftStore,
            screenCapturePreflightService,
            screenshotSelectionOverlayService,
            screenshotImageCaptureService,
            diagnostics);
        var windowCoordinator = new WindowCoordinator(diagnostics, recordingLifecycleService);
        var trayShell = new TrayShell(diagnostics);

        appShell = new WindowsAppShell(
            singleInstanceService,
            diagnostics,
            recordingLifecycleService,
            windowCoordinator,
            trayShell);

        if (!appShell.Initialize())
        {
            Shutdown();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        DispatcherUnhandledException -= OnDispatcherUnhandledException;
        appShell?.Dispose();
        base.OnExit(e);
    }

    private void OnDispatcherUnhandledException(object? sender, DispatcherUnhandledExceptionEventArgs e)
    {
        diagnostics?.Error("app", "unhandled dispatcher exception", e.Exception);
    }
}
