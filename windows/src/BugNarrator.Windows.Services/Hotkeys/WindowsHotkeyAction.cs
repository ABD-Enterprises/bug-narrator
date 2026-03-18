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
