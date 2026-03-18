namespace BugNarrator.Windows.Services.Hotkeys;

public interface IWindowsHotkeyPlatform : IDisposable
{
    event EventHandler<WindowsHotkeyAction>? HotkeyPressed;
    WindowsHotkeyRegistrationAttempt Register(WindowsHotkeyAction action, WindowsHotkeyShortcut shortcut);
    void Unregister(WindowsHotkeyAction action);
    void UnregisterAll();
}
