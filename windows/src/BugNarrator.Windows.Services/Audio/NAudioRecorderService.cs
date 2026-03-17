using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

public sealed class NAudioRecorderService : IAudioRecorderService
{
    private readonly object syncRoot = new();
    private TaskCompletionSource? stopCompletionSource;
    private WaveInEvent? waveInEvent;
    private WaveFileWriter? waveWriter;

    public bool IsRecording { get; private set; }

    public void Dispose()
    {
        CleanupRecorder();
    }

    public Task StartAsync(string audioFilePath, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (syncRoot)
        {
            if (IsRecording)
            {
                throw new InvalidOperationException("A recording session is already active.");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(audioFilePath)!);

            waveInEvent = new WaveInEvent
            {
                BufferMilliseconds = 125,
                DeviceNumber = 0,
                WaveFormat = new WaveFormat(16000, 16, 1),
            };
            waveInEvent.DataAvailable += OnDataAvailable;
            waveInEvent.RecordingStopped += OnRecordingStopped;

            waveWriter = new WaveFileWriter(audioFilePath, waveInEvent.WaveFormat);
            stopCompletionSource = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

            try
            {
                waveInEvent.StartRecording();
                IsRecording = true;
            }
            catch
            {
                CleanupRecorder();
                throw;
            }
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (syncRoot)
        {
            if (!IsRecording || waveInEvent is null)
            {
                return Task.CompletedTask;
            }

            waveInEvent.StopRecording();
            return stopCompletionSource?.Task ?? Task.CompletedTask;
        }
    }

    private void CleanupRecorder()
    {
        lock (syncRoot)
        {
            if (waveInEvent is not null)
            {
                waveInEvent.DataAvailable -= OnDataAvailable;
                waveInEvent.RecordingStopped -= OnRecordingStopped;
                waveInEvent.Dispose();
                waveInEvent = null;
            }

            waveWriter?.Dispose();
            waveWriter = null;
            stopCompletionSource = null;
            IsRecording = false;
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        lock (syncRoot)
        {
            waveWriter?.Write(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
            waveWriter?.Flush();
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs eventArgs)
    {
        TaskCompletionSource? completionSource;

        lock (syncRoot)
        {
            completionSource = stopCompletionSource;
            CleanupRecorder();
        }

        if (eventArgs.Exception is null)
        {
            completionSource?.TrySetResult();
            return;
        }

        completionSource?.TrySetException(eventArgs.Exception);
    }
}
