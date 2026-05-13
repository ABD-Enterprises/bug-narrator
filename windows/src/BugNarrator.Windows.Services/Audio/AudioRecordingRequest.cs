namespace BugNarrator.Windows.Services.Audio;

public sealed record AudioRecordingRequest(
    AudioRecordingSource Source,
    int? MicrophoneDeviceNumber)
{
    public static AudioRecordingRequest ForMicrophone(int deviceNumber)
    {
        return new AudioRecordingRequest(AudioRecordingSource.Microphone, deviceNumber);
    }

    public static AudioRecordingRequest ForSystemAudio()
    {
        return new AudioRecordingRequest(AudioRecordingSource.SystemAudio, MicrophoneDeviceNumber: null);
    }
}
