using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Capture;
using System.Windows.Threading;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Permissions;
using BugNarrator.Windows.Services.Review;
using BugNarrator.Windows.Services.Secrets;
using BugNarrator.Windows.Services.Shell;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using BugNarrator.Windows.Services.Transcription;
using BugNarrator.Windows.Shell;
using BugNarrator.Windows.Tray;
using BugNarrator.Windows.Capture;
using BugNarrator.Windows.Hotkeys;
using System.Windows;

namespace BugNarrator.Windows;

public partial class App : Application
{
    private WindowsAppShell? appShell;
    private WindowsDiagnostics? diagnostics;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        try
        {
            if (WindowsSmokeProbe.TryWriteReport(e.Args, out var smokeExitCode))
            {
                Shutdown(smokeExitCode);
                return;
            }
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine($"BugNarrator Windows smoke probe failed: {exception.Message}");
            Shutdown(1);
            return;
        }

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
        var completedSessionStore = new FileCompletedSessionStore(storagePaths);
        var settingsStore = new FileWindowsAppSettingsStore(storagePaths);
        var secretStore = new DpapiSecretStore(storagePaths, diagnostics);
        var transcriptionClient = new OpenAiTranscriptionClient();
        var issueExtractionService = new OpenAiIssueExtractionService(diagnostics);
        var gitHubExportProvider = new GitHubExportProvider(diagnostics);
        var jiraExportProvider = new JiraExportProvider(diagnostics);
        var issueExportService = new IssueExportService(gitHubExportProvider, jiraExportProvider);
        var sessionBundleExporter = new FileSessionBundleExporter(storagePaths, diagnostics);
        var debugBundleExporter = new FileDebugBundleExporter(storagePaths, settingsStore, diagnostics);
        var reviewSessionActionService = new ReviewSessionActionService(
            completedSessionStore,
            settingsStore,
            secretStore,
            issueExtractionService,
            issueExportService,
            sessionBundleExporter,
            debugBundleExporter,
            diagnostics);
        var recordingLifecycleService = new RecordingLifecycleService(
            audioRecorderService,
            microphonePreflightService,
            sessionDraftStore,
            completedSessionStore,
            screenCapturePreflightService,
            screenshotSelectionOverlayService,
            screenshotImageCaptureService,
            settingsStore,
            secretStore,
            transcriptionClient,
            diagnostics);
        var hotkeyPlatform = new Win32GlobalHotkeyPlatform();
        var hotkeyService = new WindowsGlobalHotkeyService(
            settingsStore,
            hotkeyPlatform,
            recordingLifecycleService,
            diagnostics);
        var windowCoordinator = new WindowCoordinator(
            diagnostics,
            recordingLifecycleService,
            completedSessionStore,
            reviewSessionActionService,
            settingsStore,
            hotkeyService,
            secretStore,
            transcriptionClient);
        var trayShell = new TrayShell(diagnostics);

        appShell = new WindowsAppShell(
            singleInstanceService,
            diagnostics,
            hotkeyService,
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
