using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Audio;

public interface IRecordingLifecycleService : IDisposable
{
    RecordingControlState CurrentState { get; }
    event EventHandler<RecordingControlState>? StateChanged;
    Task StartRecordingAsync(CancellationToken cancellationToken = default);
    Task StopRecordingAsync(CancellationToken cancellationToken = default);
    Task<ScreenshotCaptureResult> CaptureScreenshotAsync(CancellationToken cancellationToken = default);
}
