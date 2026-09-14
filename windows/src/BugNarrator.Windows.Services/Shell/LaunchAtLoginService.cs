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

    /// <summary>
    /// The Windows Settings Startup page (and Task Manager) do not remove Run values; they record a
    /// verdict in ExplorerStartupApprovedRun — a binary value whose first byte is 0x02 for enabled
    /// and 0x03 for disabled. Null when no verdict exists, which counts as enabled.
    /// </summary>
    bool? GetStartupApproved(string name);
    void SetStartupApproved(string name, bool approved);
    void DeleteStartupApproved(string name);
}

/// <summary>
/// Per-user launch at login through HKCU\...\CurrentVersion\Run — the same mechanism the Windows
/// Settings app's Startup page lists, so the user can also see and change it there. No elevation,
/// no Task Scheduler.
/// </summary>
public sealed class LaunchAtLoginService : ILaunchAtLoginService
{
    public const string ValueName = "BugNarrator";

    // Exposed so a test can pin the exact keys; a fake registry cannot catch a wrong path.
    public const string RunKeyPathValue = @"Software\Microsoft\Windows\CurrentVersion\Run";
    public const string StartupApprovedKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";

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
            var isOurs = string.Equals(registered, command, StringComparison.OrdinalIgnoreCase);
            // A Run value the user disabled on the Windows Settings Startup page is still present but
            // does not launch; reading it as enabled would contradict what Settings shows.
            var approved = registry.GetStartupApproved(ValueName) ?? true;
            return isOurs && approved ? LaunchAtLoginStatus.Enabled : LaunchAtLoginStatus.Disabled;
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
                // Clear a Settings-page "disabled" verdict, or the value is present but never runs.
                registry.SetStartupApproved(ValueName, approved: true);
            }
            else if (string.Equals(registry.GetValue(ValueName), command, StringComparison.OrdinalIgnoreCase))
            {
                // Only this copy's registration is ours to remove; a value pointing at another install is
                // that install's, and CurrentStatus already reports it as disabled here.
                registry.DeleteValue(ValueName);
                registry.DeleteStartupApproved(ValueName);
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
        private const string RunKeyPath = RunKeyPathValue;

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

        private const string StartupApprovedPath = StartupApprovedKeyPath;

        public bool? GetStartupApproved(string name)
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupApprovedPath, writable: false);
            return key?.GetValue(name) is byte[] { Length: > 0 } verdict ? verdict[0] != 0x03 : null;
        }

        public void SetStartupApproved(string name, bool approved)
        {
            using var key = Registry.CurrentUser.CreateSubKey(StartupApprovedPath, writable: true)
                ?? throw new IOException("The startup-approved registry key could not be opened for writing.");
            // Explorer's own shape: verdict byte, then eleven bytes it uses for a timestamp; zeros are accepted.
            var verdict = new byte[12];
            verdict[0] = approved ? (byte)0x02 : (byte)0x03;
            key.SetValue(name, verdict, RegistryValueKind.Binary);
        }

        public void DeleteStartupApproved(string name)
        {
            using var key = Registry.CurrentUser.OpenSubKey(StartupApprovedPath, writable: true);
            key?.DeleteValue(name, throwOnMissingValue: false);
        }
    }
}
