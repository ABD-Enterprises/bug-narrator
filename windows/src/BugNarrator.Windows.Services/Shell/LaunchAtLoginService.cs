using Microsoft.Win32;

namespace BugNarrator.Windows.Services.Shell;

/// <summary>
/// The Windows reading of macOS LaunchAtLoginStatus: enabled/disabled are the normal states; unavailable
/// carries the reason and hides the toggle. Windows has no "requires approval" state — the Run key
/// takes effect at the next sign-in with no consent dialog — so that case does not exist here.
/// </summary>
public sealed record LaunchAtLoginStatus(bool IsEnabled, bool IsAvailable, string? Message)
{
    public static LaunchAtLoginStatus Enabled { get; } = new(true, true, null);
    public static LaunchAtLoginStatus Disabled { get; } = new(false, true, null);
    public static LaunchAtLoginStatus Unavailable(string message) => new(false, false, message);
}

public interface ILaunchAtLoginService
{
    LaunchAtLoginStatus CurrentStatus();
    LaunchAtLoginStatus SetEnabled(bool enabled);
}

/// <summary>The registry slice the service touches, so tests never reach the real HKCU.</summary>
public interface IRunKeyRegistry
{
    string? GetValue(string name);
    void SetValue(string name, string command);
    void DeleteValue(string name);
}

/// <summary>
/// Per-user launch at login through HKCU\...\CurrentVersion\Run — the same mechanism the Windows
/// Settings app's Startup page lists, so the user can also see and change it there. No elevation,
/// no Task Scheduler.
/// </summary>
public sealed class LaunchAtLoginService : ILaunchAtLoginService
{
    public const string ValueName = "BugNarrator";

    private readonly IRunKeyRegistry registry;
    private readonly Func<string?> executablePath;

    public LaunchAtLoginService(IRunKeyRegistry registry, Func<string?> executablePath)
    {
        this.registry = registry;
        this.executablePath = executablePath;
    }

    public static LaunchAtLoginService ForCurrentUser() =>
        new(new CurrentUserRunKeyRegistry(), () => Environment.ProcessPath);

    public LaunchAtLoginStatus CurrentStatus()
    {
        var command = Command();
        if (command is null)
        {
            return LaunchAtLoginStatus.Unavailable(
                "Launch at login is unavailable for this app copy because its executable path could not be resolved.");
        }

        try
        {
            var registered = registry.GetValue(ValueName);
            return string.Equals(registered, command, StringComparison.OrdinalIgnoreCase)
                ? LaunchAtLoginStatus.Enabled
                : LaunchAtLoginStatus.Disabled;
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            return LaunchAtLoginStatus.Unavailable(
                $"Launch at login is unavailable because the startup registry key could not be read: {exception.Message}");
        }
    }

    public LaunchAtLoginStatus SetEnabled(bool enabled)
    {
        var command = Command();
        if (command is null)
        {
            return CurrentStatus();
        }

        try
        {
            if (enabled)
            {
                registry.SetValue(ValueName, command);
            }
            else
            {
                registry.DeleteValue(ValueName);
            }
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException or IOException)
        {
            return LaunchAtLoginStatus.Unavailable(
                $"Launch at login could not be changed because the startup registry key is not writable: {exception.Message}");
        }

        return CurrentStatus();
    }

    /// <summary>Quoted so a path with spaces survives the shell that runs Run entries.</summary>
    private string? Command()
    {
        var path = executablePath();
        return string.IsNullOrWhiteSpace(path) ? null : $"\"{path}\"";
    }

    private sealed class CurrentUserRunKeyRegistry : IRunKeyRegistry
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

        public string? GetValue(string name)
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            return key?.GetValue(name) as string;
        }

        public void SetValue(string name, string command)
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath, writable: true)
                ?? throw new IOException("The startup registry key could not be opened for writing.");
            key.SetValue(name, command, RegistryValueKind.String);
        }

        public void DeleteValue(string name)
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true);
            key?.DeleteValue(name, throwOnMissingValue: false);
        }
    }
}
