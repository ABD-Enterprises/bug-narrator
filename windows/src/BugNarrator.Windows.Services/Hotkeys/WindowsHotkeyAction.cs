namespace BugNarrator.Windows.Services.Hotkeys;

public enum WindowsHotkeyAction
{
    StartRecording = 1,
    StopRecording = 2,
    CaptureScreenshot = 3,
}

public static class WindowsHotkeyActionExtensions
{
    public static IReadOnlyList<WindowsHotkeyAction> All { get; } =
    [
        WindowsHotkeyAction.StartRecording,
        WindowsHotkeyAction.StopRecording,
        WindowsHotkeyAction.CaptureScreenshot,
    ];

    /// <summary>
    /// Vetted default offered as a one-click suggestion on empty hotkey rows, as macOS
    /// HotkeyAction.suggestedShortcut does (⌘⌥⌃F / ⌘⌥⌃⇧F / ⌘⌥⌃⇧S). Ctrl+Alt(+Shift) is the Windows
    /// equivalent that avoids the shell's own Win-key combinations.
    /// </summary>
    public static WindowsHotkeyShortcut SuggestedShortcut(this WindowsHotkeyAction action) => action switch
    {
        WindowsHotkeyAction.StartRecording => new WindowsHotkeyShortcut(
            0x46, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt),
        WindowsHotkeyAction.StopRecording => new WindowsHotkeyShortcut(
            0x46, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt | WindowsHotkeyModifiers.Shift),
        WindowsHotkeyAction.CaptureScreenshot => new WindowsHotkeyShortcut(
            0x53, WindowsHotkeyModifiers.Control | WindowsHotkeyModifiers.Alt | WindowsHotkeyModifiers.Shift),
        _ => WindowsHotkeyShortcut.NotSet,
    };

    public static string DisplayName(this WindowsHotkeyAction action)
    {
        return action switch
        {
            WindowsHotkeyAction.StartRecording => "Start Recording",
            WindowsHotkeyAction.StopRecording => "Stop Recording",
            WindowsHotkeyAction.CaptureScreenshot => "Capture Screenshot",
            _ => action.ToString(),
        };
    }
}
