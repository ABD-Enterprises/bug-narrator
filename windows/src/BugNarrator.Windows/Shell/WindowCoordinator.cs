using BugNarrator.Windows.Services.Shell;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Permissions;
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
    private readonly IAudioInputDeviceCatalog audioInputDeviceCatalog;
    private readonly ICompletedSessionStore completedSessionStore;
    private readonly WindowsDiagnostics diagnostics;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly IReviewSessionActionService reviewSessionActionService;
    private readonly ISecretStore secretStore;
    private readonly IWindowsGlobalHotkeyService hotkeyService;
    private readonly IMicrophonePreflightService microphonePreflightService;
    private readonly IWindowsAppSettingsStore settingsStore;
    private readonly ITranscriptionClient transcriptionClient;
    private AboutWindow? aboutWindow;
    private RecordingWorkflowState lastObservedWorkflowState;
    private RecordingControlsWindow? recordingControlsWindow;
    private SessionLibraryWindow? sessionLibraryWindow;
    private SettingsWindow? settingsWindow;
    private WelcomeWindow? welcomeWindow;

    public WindowCoordinator(
        WindowsDiagnostics diagnostics,
        IRecordingLifecycleService recordingLifecycleService,
        ICompletedSessionStore completedSessionStore,
        IReviewSessionActionService reviewSessionActionService,
        IWindowsAppSettingsStore settingsStore,
        IWindowsGlobalHotkeyService hotkeyService,
        ISecretStore secretStore,
        ITranscriptionClient transcriptionClient,
        IAudioInputDeviceCatalog audioInputDeviceCatalog,
        IMicrophonePreflightService microphonePreflightService)
    {
        this.audioInputDeviceCatalog = audioInputDeviceCatalog;
        this.microphonePreflightService = microphonePreflightService;
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
        CloseWindow(welcomeWindow);
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

    public void ToggleRecordingControls()
    {
        if (recordingControlsWindow is { IsLoaded: true, IsVisible: true } && recordingControlsWindow.IsActive)
        {
            recordingControlsWindow.Hide();
            diagnostics.Info("windows", "recording controls window hidden from tray");
            return;
        }

        ShowRecordingControls();
    }

    public async Task<int> CountSessionsAsync()
    {
        return (await completedSessionStore.GetAllAsync()).Count;
    }

    public async Task AddSampleSessionAndShowLibraryAsync()
    {
        await completedSessionStore.SaveAsync(SampleSession.Make(completedSessionStore.SessionsDirectory));
        ShowSessionLibrary();
    }

    public void ShowSessionLibrary()
    {
        if (sessionLibraryWindow is null || !sessionLibraryWindow.IsLoaded)
        {
            sessionLibraryWindow = new SessionLibraryWindow(
                completedSessionStore,
                reviewSessionActionService,
                settingsStore,
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

    /// <summary>
    /// Whether the first-run tour should open unprompted now (macOS BugNarratorApp.shouldPresentWelcome):
    /// the FirstRunFunnel rule over persisted settings, the saved credential, and the session count.
    /// Microphone state is "not yet checked" (false) at startup, as macOS maps notDetermined.
    /// </summary>
    public async Task<bool> ShouldPresentWelcomeAsync()
    {
        var settings = await settingsStore.LoadAsync();
        var credential = await secretStore.GetAsync(SecretKeys.OpenAiApiKey);
        var sessionCount = await CountSessionsAsync();
        return FirstRunFunnel.ShouldPresentWelcome(
            settings.HasCompletedWelcome,
            sessionCount,
            new OnboardingSnapshot(
                HasUsableAiProviderCredential: settings.HasUsableAiProviderCredential(credential),
                ProviderConfigurationIsCompatible: settings.AiProviderCompatibilityIssue is null,
                MicrophoneAuthorized: false,
                HasAnyCaptureHotkeyAssigned: settings.HasAnyCaptureHotkeyAssigned));
    }

    public void ShowWelcome()
    {
        if (welcomeWindow is null || !welcomeWindow.IsLoaded)
        {
            welcomeWindow = new WelcomeWindow(
                settingsStore,
                secretStore,
                hotkeyService,
                microphonePreflightService,
                audioInputDeviceCatalog,
                diagnostics,
                ShowSettings);
            welcomeWindow.Closed += (_, _) =>
            {
                diagnostics.Info("windows", "welcome window closed");
                welcomeWindow = null;
            };
            diagnostics.Info("windows", "welcome window created");
        }

        ShowAndActivate(welcomeWindow);
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
                diagnostics,
                audioInputDeviceCatalog,
                LaunchAtLoginService.ForCurrentUser());
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
