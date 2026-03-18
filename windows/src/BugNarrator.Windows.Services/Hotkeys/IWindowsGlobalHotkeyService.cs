using BugNarrator.Windows.Services.Settings;

namespace BugNarrator.Windows.Services.Hotkeys;

public interface IWindowsGlobalHotkeyService : IDisposable
{
    WindowsHotkeyRuntimeSnapshot CurrentSnapshot { get; }
    event EventHandler<WindowsHotkeyRuntimeSnapshot>? StateChanged;
    Task<WindowsHotkeyRuntimeSnapshot> InitializeAsync(CancellationToken cancellationToken = default);
    Task<WindowsHotkeyRuntimeSnapshot> ApplySettingsAsync(
        WindowsAppSettings settings,
        CancellationToken cancellationToken = default);
}
