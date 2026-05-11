using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

public sealed class NAudioInputDeviceCatalog : IAudioInputDeviceCatalog
{
    public IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices()
    {
        var devices = new List<AudioInputDeviceOption>();

        for (var index = 0; index < WaveInEvent.DeviceCount; index++)
        {
            var capabilities = WaveInEvent.GetCapabilities(index);
            devices.Add(new AudioInputDeviceOption(
                index,
                string.IsNullOrWhiteSpace(capabilities.ProductName)
                    ? $"Microphone {index + 1}"
                    : capabilities.ProductName.Trim()));
        }

        return devices;
    }
}
