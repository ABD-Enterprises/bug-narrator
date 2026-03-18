namespace BugNarrator.Windows.Services.Hotkeys;

public sealed record WindowsHotkeyRegistrationStatus(
    WindowsHotkeyAction Action,
    WindowsHotkeyShortcut Shortcut,
    WindowsHotkeyRegistrationState State,
    string Message,
    int? Win32ErrorCode = null);

public sealed class WindowsHotkeyRuntimeSnapshot
{
    private readonly IReadOnlyDictionary<WindowsHotkeyAction, WindowsHotkeyRegistrationStatus> statuses;

    public WindowsHotkeyRuntimeSnapshot(IEnumerable<WindowsHotkeyRegistrationStatus> statuses)
    {
        var statusLookup = new Dictionary<WindowsHotkeyAction, WindowsHotkeyRegistrationStatus>();

        foreach (var action in WindowsHotkeyActionExtensions.All)
        {
            statusLookup[action] = CreateDefaultStatus(action);
        }

        foreach (var status in statuses)
        {
            statusLookup[status.Action] = status;
        }

        this.statuses = statusLookup;
    }

    public static WindowsHotkeyRuntimeSnapshot Empty { get; } =
        new WindowsHotkeyRuntimeSnapshot(Array.Empty<WindowsHotkeyRegistrationStatus>());

    public IReadOnlyList<WindowsHotkeyRegistrationStatus> Statuses =>
        WindowsHotkeyActionExtensions.All
            .Select(GetStatus)
            .ToArray();

    public bool HasProblems =>
        Statuses.Any(status => status.State is WindowsHotkeyRegistrationState.Invalid
            or WindowsHotkeyRegistrationState.Conflict
            or WindowsHotkeyRegistrationState.Unavailable);

    public WindowsHotkeyRegistrationStatus GetStatus(WindowsHotkeyAction action)
    {
        return statuses.TryGetValue(action, out var status)
            ? status
            : CreateDefaultStatus(action);
    }

    private static WindowsHotkeyRegistrationStatus CreateDefaultStatus(WindowsHotkeyAction action)
    {
        return new WindowsHotkeyRegistrationStatus(
            action,
            WindowsHotkeyShortcut.NotSet,
            WindowsHotkeyRegistrationState.NotSet,
            "Not Set. Configure a shortcut in Settings if you want global access.");
    }
}
