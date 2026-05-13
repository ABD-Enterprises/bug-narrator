namespace BugNarrator.Windows.Services.Audio;

public enum AudioRecordingSource
{
    Microphone,
    SystemAudio,
    MicrophoneAndSystemAudio,
}

public sealed record AudioRecordingSourceProfile(
    AudioRecordingSource Source,
    string StorageValue,
    string DisplayName,
    string Description,
    bool UsesMicrophone,
    bool UsesSystemAudio)
{
    public static IReadOnlyList<AudioRecordingSourceProfile> All { get; } =
    [
        new(
            AudioRecordingSource.Microphone,
            "microphone",
            "Microphone",
            "Record the selected microphone only.",
            UsesMicrophone: true,
            UsesSystemAudio: false),
        new(
            AudioRecordingSource.SystemAudio,
            "systemAudio",
            "System Audio",
            "Record audio currently playing through the default Windows output device.",
            UsesMicrophone: false,
            UsesSystemAudio: true),
        new(
            AudioRecordingSource.MicrophoneAndSystemAudio,
            "microphoneAndSystemAudio",
            "Microphone + System Audio",
            "Mixed capture is tracked as a follow-up; choose this to see the explicit limitation.",
            UsesMicrophone: true,
            UsesSystemAudio: true),
    ];

    public static AudioRecordingSourceProfile Default => All[0];

    public static AudioRecordingSourceProfile FromStorageValue(string? value)
    {
        return All.FirstOrDefault(profile =>
            string.Equals(profile.StorageValue, value, StringComparison.OrdinalIgnoreCase))
            ?? Default;
    }

    public override string ToString()
    {
        return DisplayName;
    }
}
