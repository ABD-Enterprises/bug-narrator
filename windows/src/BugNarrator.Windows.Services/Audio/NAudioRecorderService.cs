using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

public sealed class NAudioRecorderService : IAudioRecorderService
{
    private readonly object syncRoot = new();
    private TaskCompletionSource? stopCompletionSource;
    private IWaveIn? activeCapture;
    private WaveFileWriter? waveWriter;

    public bool IsRecording { get; private set; }

    public void Dispose()
    {
        CleanupRecorder();
    }

    public Task StartAsync(string audioFilePath, AudioRecordingRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (syncRoot)
        {
            if (IsRecording)
            {
                throw new InvalidOperationException("A recording session is already active.");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(audioFilePath)!);

            activeCapture = CreateCapture(request);
            activeCapture.DataAvailable += OnDataAvailable;
            activeCapture.RecordingStopped += OnRecordingStopped;

            waveWriter = new WaveFileWriter(audioFilePath, activeCapture.WaveFormat);
            stopCompletionSource = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

            try
            {
                activeCapture.StartRecording();
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
            if (!IsRecording || activeCapture is null)
            {
                return Task.CompletedTask;
            }

            activeCapture.StopRecording();
            return stopCompletionSource?.Task ?? Task.CompletedTask;
        }
    }

    private static IWaveIn CreateCapture(AudioRecordingRequest request)
    {
        return request.Source switch
        {
            AudioRecordingSource.Microphone => CreateMicrophoneCapture(request),
            AudioRecordingSource.SystemAudio => new WasapiLoopbackCapture(),
            AudioRecordingSource.MicrophoneAndSystemAudio =>
                throw new NotSupportedException(
                    "Microphone plus system audio recording is not implemented yet. Choose Microphone or System Audio for this build."),
            _ => throw new InvalidOperationException("Unsupported recording source."),
        };
    }

    private static WaveInEvent CreateMicrophoneCapture(AudioRecordingRequest request)
    {
        if (request.MicrophoneDeviceNumber is null)
        {
            throw new InvalidOperationException("A microphone device is required for microphone recording.");
        }

        return new WaveInEvent
        {
            BufferMilliseconds = 125,
            DeviceNumber = request.MicrophoneDeviceNumber.Value,
            WaveFormat = new WaveFormat(16000, 16, 1),
        };
    }

    private void CleanupRecorder()
    {
        lock (syncRoot)
        {
            if (activeCapture is not null)
            {
                activeCapture.DataAvailable -= OnDataAvailable;
                activeCapture.RecordingStopped -= OnRecordingStopped;
                activeCapture.Dispose();
                activeCapture = null;
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
