using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Audio;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Hotkeys;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class WindowsHotkeySettingsTests : IDisposable
{
    private readonly string rootDirectory;
    private readonly AppStoragePaths storagePaths;

    public WindowsHotkeySettingsTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));

        Directory.CreateDirectory(storagePaths.RootDirectory);
        Directory.CreateDirectory(storagePaths.SessionsDirectory);
        Directory.CreateDirectory(storagePaths.LogsDirectory);
    }

    [Fact]
    public void Validate_WithDuplicateShortcuts_ReturnsConflictForBothActions()
    {
        var duplicateShortcut = new WindowsHotkeyShortcut(0x53, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift);
        var settings = WindowsAppSettings.Default with
        {
            StartRecordingHotkey = duplicateShortcut,
            StopRecordingHotkey = duplicateShortcut,
        };

        var issues = WindowsHotkeySettingsValidator.Validate(settings);

        Assert.Contains(issues, issue => issue.Action == WindowsHotkeyAction.StartRecording
            && issue.State == WindowsHotkeyRegistrationState.Conflict);
        Assert.Contains(issues, issue => issue.Action == WindowsHotkeyAction.StopRecording
            && issue.State == WindowsHotkeyRegistrationState.Conflict);
    }

    [Fact]
    public void Validate_WithModifierOnlyOrMissingModifier_ReturnsInvalidIssues()
    {
        var settings = WindowsAppSettings.Default with
        {
            StartRecordingHotkey = new WindowsHotkeyShortcut(0x46, WindowsHotkeyModifiers.None),
            StopRecordingHotkey = new WindowsHotkeyShortcut(0x10, WindowsHotkeyModifiers.Control),
        };

        var issues = WindowsHotkeySettingsValidator.Validate(settings);

        Assert.Contains(issues, issue => issue.Action == WindowsHotkeyAction.StartRecording
            && issue.State == WindowsHotkeyRegistrationState.Invalid);
        Assert.Contains(issues, issue => issue.Action == WindowsHotkeyAction.StopRecording
            && issue.State == WindowsHotkeyRegistrationState.Invalid);
    }

    [Fact]
    public async Task FileWindowsAppSettingsStore_RoundTripsHotkeyAssignments()
    {
        var store = new FileWindowsAppSettingsStore(storagePaths);
        var settings = WindowsAppSettings.Default with
        {
            StartRecordingHotkey = new WindowsHotkeyShortcut(0x46, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt),
            StopRecordingHotkey = new WindowsHotkeyShortcut(0x47, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift),
            ScreenshotHotkey = new WindowsHotkeyShortcut(0x53, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift),
        };

        await store.SaveAsync(settings);
        var loaded = await store.LoadAsync();

        Assert.Equal(settings.StartRecordingHotkey.Normalize(), loaded.EffectiveStartRecordingHotkey);
        Assert.Equal(settings.StopRecordingHotkey.Normalize(), loaded.EffectiveStopRecordingHotkey);
        Assert.Equal(settings.ScreenshotHotkey.Normalize(), loaded.EffectiveScreenshotHotkey);
    }

    [Fact]
    public async Task ApplySettingsAsync_RegistersUniqueHotkeysAndRoutesInvocations()
    {
        var platform = new FakeWindowsHotkeyPlatform();
        var recordingLifecycle = new FakeRecordingLifecycleService();
        var service = new WindowsGlobalHotkeyService(
            new FakeWindowsAppSettingsStore(),
            platform,
            recordingLifecycle,
            new WindowsDiagnostics(storagePaths));
        var settings = WindowsAppSettings.Default with
        {
            StartRecordingHotkey = new WindowsHotkeyShortcut(0x46, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt),
            StopRecordingHotkey = new WindowsHotkeyShortcut(0x47, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift),
            ScreenshotHotkey = new WindowsHotkeyShortcut(0x53, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift),
        };

        var snapshot = await service.ApplySettingsAsync(settings);
        platform.RaisePressed(WindowsHotkeyAction.StartRecording);
        platform.RaisePressed(WindowsHotkeyAction.StopRecording);
        platform.RaisePressed(WindowsHotkeyAction.CaptureScreenshot);

        Assert.Equal(WindowsHotkeyRegistrationState.Registered, snapshot.GetStatus(WindowsHotkeyAction.StartRecording).State);
        Assert.Equal(WindowsHotkeyRegistrationState.Registered, snapshot.GetStatus(WindowsHotkeyAction.StopRecording).State);
        Assert.Equal(WindowsHotkeyRegistrationState.Registered, snapshot.GetStatus(WindowsHotkeyAction.CaptureScreenshot).State);
        Assert.Equal(1, recordingLifecycle.StartCallCount);
        Assert.Equal(1, recordingLifecycle.StopCallCount);
        Assert.Equal(1, recordingLifecycle.ScreenshotCallCount);

        service.Dispose();
    }

    [Fact]
    public async Task ApplySettingsAsync_WhenPlatformRejectsShortcut_MarksActionUnavailable()
    {
        var platform = new FakeWindowsHotkeyPlatform();
        platform.Failures[WindowsHotkeyAction.CaptureScreenshot] = new WindowsHotkeyRegistrationAttempt(
            IsRegistered: false,
            Message: "Windows could not register Ctrl+Shift+S because another app is already using that shortcut.",
            Win32ErrorCode: 1409);

        var service = new WindowsGlobalHotkeyService(
            new FakeWindowsAppSettingsStore(),
            platform,
            new FakeRecordingLifecycleService(),
            new WindowsDiagnostics(storagePaths));
        var settings = WindowsAppSettings.Default with
        {
            StartRecordingHotkey = new WindowsHotkeyShortcut(0x46, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt),
            ScreenshotHotkey = new WindowsHotkeyShortcut(0x53, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Shift),
        };

        var snapshot = await service.ApplySettingsAsync(settings);

        Assert.Equal(WindowsHotkeyRegistrationState.Registered, snapshot.GetStatus(WindowsHotkeyAction.StartRecording).State);
        Assert.Equal(WindowsHotkeyRegistrationState.Unavailable, snapshot.GetStatus(WindowsHotkeyAction.CaptureScreenshot).State);
        Assert.Equal(1409, snapshot.GetStatus(WindowsHotkeyAction.CaptureScreenshot).Win32ErrorCode);

        service.Dispose();
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }

    private sealed class FakeWindowsAppSettingsStore : IWindowsAppSettingsStore
    {
        public WindowsAppSettings Settings { get; set; } = WindowsAppSettings.Default;

        public ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default)
        {
            return ValueTask.FromResult(Settings);
        }

        public ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default)
        {
            Settings = settings;
            return ValueTask.CompletedTask;
        }
    }

    private sealed class FakeWindowsHotkeyPlatform : IWindowsHotkeyPlatform
    {
        public Dictionary<WindowsHotkeyAction, WindowsHotkeyRegistrationAttempt> Failures { get; } = [];
        public Dictionary<WindowsHotkeyAction, WindowsHotkeyShortcut> RegisteredShortcuts { get; } = [];

        public event EventHandler<WindowsHotkeyAction>? HotkeyPressed;

        public WindowsHotkeyRegistrationAttempt Register(WindowsHotkeyAction action, WindowsHotkeyShortcut shortcut)
        {
            if (Failures.TryGetValue(action, out var failure))
            {
                return failure;
            }

            RegisteredShortcuts[action] = shortcut;
            return new WindowsHotkeyRegistrationAttempt(
                IsRegistered: true,
                Message: $"{action.DisplayName()} is active globally as {shortcut.DisplayString}.");
        }

        public void Unregister(WindowsHotkeyAction action)
        {
            RegisteredShortcuts.Remove(action);
        }

        public void UnregisterAll()
        {
            RegisteredShortcuts.Clear();
        }

        public void Dispose()
        {
            RegisteredShortcuts.Clear();
            Failures.Clear();
        }

        public void RaisePressed(WindowsHotkeyAction action)
        {
            HotkeyPressed?.Invoke(this, action);
        }
    }

    private sealed class FakeRecordingLifecycleService : IRecordingLifecycleService
    {
        public RecordingControlState CurrentState => RecordingControlState.Idle();

        public int ScreenshotCallCount { get; private set; }
        public int StartCallCount { get; private set; }
        public int StopCallCount { get; private set; }

        public event EventHandler<RecordingControlState>? StateChanged
        {
            add { }
            remove { }
        }

        public void Dispose()
        {
        }

        public Task StartRecordingAsync(CancellationToken cancellationToken = default)
        {
            StartCallCount++;
            return Task.CompletedTask;
        }

        public Task StopRecordingAsync(CancellationToken cancellationToken = default)
        {
            StopCallCount++;
            return Task.CompletedTask;
        }

        public Task<ScreenshotCaptureResult> CaptureScreenshotAsync(CancellationToken cancellationToken = default)
        {
            ScreenshotCallCount++;
            return Task.FromResult(new ScreenshotCaptureResult(
                ScreenshotCaptureResultStatus.Cancelled,
                "cancelled",
                Screenshot: null));
        }
    }
}
