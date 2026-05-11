namespace BugNarrator.Windows.Services.Audio;

public sealed record AudioInputDeviceOption(
    int DeviceNumber,
    string DisplayName);
