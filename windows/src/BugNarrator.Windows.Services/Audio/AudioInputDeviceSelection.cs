namespace BugNarrator.Windows.Services.Audio;

public sealed record AudioInputDeviceSelection(
    bool IsResolved,
    int DeviceNumber,
    string DisplayName,
    string? ErrorMessage)
{
    public static AudioInputDeviceSelection Resolve(
        string? preferredDeviceName,
        IReadOnlyList<AudioInputDeviceOption> availableDevices)
    {
        if (availableDevices.Count == 0)
        {
            return new AudioInputDeviceSelection(
                IsResolved: false,
                DeviceNumber: -1,
                DisplayName: string.Empty,
                ErrorMessage: "No microphone device is available.");
        }

        if (string.IsNullOrWhiteSpace(preferredDeviceName))
        {
            var fallbackDevice = availableDevices[0];
            return new AudioInputDeviceSelection(
                IsResolved: true,
                DeviceNumber: fallbackDevice.DeviceNumber,
                DisplayName: fallbackDevice.DisplayName,
                ErrorMessage: null);
        }

        var selectedDevice = availableDevices.FirstOrDefault(device =>
            string.Equals(device.DisplayName, preferredDeviceName.Trim(), StringComparison.OrdinalIgnoreCase));

        if (selectedDevice is not null)
        {
            return new AudioInputDeviceSelection(
                IsResolved: true,
                DeviceNumber: selectedDevice.DeviceNumber,
                DisplayName: selectedDevice.DisplayName,
                ErrorMessage: null);
        }

        return new AudioInputDeviceSelection(
            IsResolved: false,
            DeviceNumber: -1,
            DisplayName: preferredDeviceName.Trim(),
            ErrorMessage: $"The saved microphone \"{preferredDeviceName.Trim()}\" is unavailable. Open Settings and choose an available input device.");
    }
}
