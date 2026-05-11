namespace BugNarrator.Windows.Services.Audio;

public interface IAudioInputDeviceCatalog
{
    IReadOnlyList<AudioInputDeviceOption> GetAvailableInputDevices();
}
