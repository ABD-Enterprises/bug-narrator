namespace BugNarrator.Windows.Services.Audio;

public interface IAudioRecorderService : IDisposable
{
    bool IsRecording { get; }
    Task StartAsync(string audioFilePath, CancellationToken cancellationToken = default);
    Task StopAsync(CancellationToken cancellationToken = default);
}
