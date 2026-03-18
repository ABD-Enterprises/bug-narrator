using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Settings;

namespace BugNarrator.Windows.Services.Hotkeys;

public sealed class WindowsGlobalHotkeyService : IWindowsGlobalHotkeyService
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly IWindowsHotkeyPlatform hotkeyPlatform;
    private readonly IRecordingLifecycleService recordingLifecycleService;
    private readonly IWindowsAppSettingsStore settingsStore;
    private readonly object syncRoot = new();
    private WindowsHotkeyRuntimeSnapshot currentSnapshot = WindowsHotkeyRuntimeSnapshot.Empty;

    public WindowsGlobalHotkeyService(
        IWindowsAppSettingsStore settingsStore,
        IWindowsHotkeyPlatform hotkeyPlatform,
        IRecordingLifecycleService recordingLifecycleService,
        WindowsDiagnostics diagnostics)
    {
        this.settingsStore = settingsStore;
        this.hotkeyPlatform = hotkeyPlatform;
        this.recordingLifecycleService = recordingLifecycleService;
        this.diagnostics = diagnostics;

        hotkeyPlatform.HotkeyPressed += OnHotkeyPressed;
    }

    public WindowsHotkeyRuntimeSnapshot CurrentSnapshot
    {
        get
        {
            lock (syncRoot)
            {
                return currentSnapshot;
            }
        }
    }

    public event EventHandler<WindowsHotkeyRuntimeSnapshot>? StateChanged;

    public async Task<WindowsHotkeyRuntimeSnapshot> InitializeAsync(CancellationToken cancellationToken = default)
    {
        diagnostics.Info("hotkeys", "loading persisted Windows hotkey settings");
        var settings = await settingsStore.LoadAsync(cancellationToken);
        return await ApplySettingsAsync(settings, cancellationToken);
    }

    public Task<WindowsHotkeyRuntimeSnapshot> ApplySettingsAsync(
        WindowsAppSettings settings,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var assignments = settings.GetHotkeyAssignments();
        var issuesByAction = WindowsHotkeySettingsValidator
            .Validate(assignments)
            .ToDictionary(issue => issue.Action);
        var statuses = new List<WindowsHotkeyRegistrationStatus>();

        hotkeyPlatform.UnregisterAll();

        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            var shortcut = assignments[action].Normalize();

            if (shortcut.IsNotSet)
            {
                statuses.Add(new WindowsHotkeyRegistrationStatus(
                    action,
                    shortcut,
                    WindowsHotkeyRegistrationState.NotSet,
                    "Not Set. Configure a shortcut in Settings if you want global access."));
                continue;
            }

            if (issuesByAction.TryGetValue(action, out var issue))
            {
                diagnostics.Warning("hotkeys", $"{action.DisplayName()} shortcut rejected: {issue.Message}");
                statuses.Add(new WindowsHotkeyRegistrationStatus(
                    action,
                    shortcut,
                    issue.State,
                    issue.Message));
                continue;
            }

            var attempt = hotkeyPlatform.Register(action, shortcut);
            var state = attempt.IsRegistered
                ? WindowsHotkeyRegistrationState.Registered
                : WindowsHotkeyRegistrationState.Unavailable;

            if (attempt.IsRegistered)
            {
                diagnostics.Info("hotkeys", attempt.Message);
            }
            else
            {
                diagnostics.Warning("hotkeys", attempt.Message);
            }

            statuses.Add(new WindowsHotkeyRegistrationStatus(
                action,
                shortcut,
                state,
                attempt.Message,
                attempt.Win32ErrorCode));
        }

        var snapshot = new WindowsHotkeyRuntimeSnapshot(statuses);
        PublishSnapshot(snapshot);
        return Task.FromResult(snapshot);
    }

    public void Dispose()
    {
        hotkeyPlatform.HotkeyPressed -= OnHotkeyPressed;
        hotkeyPlatform.Dispose();
    }

    private async void OnHotkeyPressed(object? sender, WindowsHotkeyAction action)
    {
        diagnostics.Info("hotkeys", $"{action.DisplayName()} invoked via global shortcut");

        try
        {
            switch (action)
            {
                case WindowsHotkeyAction.StartRecording:
                    await recordingLifecycleService.StartRecordingAsync();
                    break;
                case WindowsHotkeyAction.StopRecording:
                    await recordingLifecycleService.StopRecordingAsync();
                    break;
                case WindowsHotkeyAction.CaptureScreenshot:
                    await recordingLifecycleService.CaptureScreenshotAsync();
                    break;
                default:
                    diagnostics.Warning("hotkeys", $"unhandled hotkey action: {action}");
                    break;
            }
        }
        catch (Exception exception)
        {
            diagnostics.Error("hotkeys", $"{action.DisplayName()} hotkey action failed", exception);
        }
    }

    private void PublishSnapshot(WindowsHotkeyRuntimeSnapshot snapshot)
    {
        lock (syncRoot)
        {
            currentSnapshot = snapshot;
        }

        StateChanged?.Invoke(this, snapshot);
    }
}
