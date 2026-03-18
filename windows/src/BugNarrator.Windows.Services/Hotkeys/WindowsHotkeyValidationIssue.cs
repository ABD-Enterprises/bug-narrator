namespace BugNarrator.Windows.Services.Hotkeys;

public sealed record WindowsHotkeyValidationIssue(
    WindowsHotkeyAction Action,
    WindowsHotkeyRegistrationState State,
    string Message);
