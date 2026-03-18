namespace BugNarrator.Windows.Services.Hotkeys;

public readonly record struct WindowsHotkeyRegistrationAttempt(
    bool IsRegistered,
    string Message,
    int? Win32ErrorCode = null);
