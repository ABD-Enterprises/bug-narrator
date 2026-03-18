namespace BugNarrator.Windows.Services.Settings;

public interface IWindowsAppSettingsStore
{
    ValueTask<WindowsAppSettings> LoadAsync(CancellationToken cancellationToken = default);
    ValueTask SaveAsync(WindowsAppSettings settings, CancellationToken cancellationToken = default);
}
