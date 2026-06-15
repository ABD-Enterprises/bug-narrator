using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

public sealed class NAudioRecorderService : IAudioRecorderService
{
    private readonly object syncRoot = new();
    private TaskCompletionSource? stopCompletionSource;
    private IWaveIn? activeCapture;
    private WaveFileWriter? waveWriter;
    private MixedAudioRecording? mixedRecording;

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

            if (request.Source == AudioRecordingSource.MicrophoneAndSystemAudio)
            {
                if (request.MicrophoneDeviceNumber is null)
                {
                    throw new InvalidOperationException(
                        "A microphone device is required for microphone plus system audio recording.");
                }

                var mixed = new MixedAudioRecording(audioFilePath, request.MicrophoneDeviceNumber.Value);
                try
                {
                    mixed.Start();
                }
                catch
                {
                    mixed.Dispose();
                    throw;
                }

                mixedRecording = mixed;
                IsRecording = true;
                return Task.CompletedTask;
            }

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

        MixedAudioRecording? mixed = null;
        lock (syncRoot)
        {
            if (mixedRecording is not null)
            {
                mixed = mixedRecording;
                mixedRecording = null;
            }
            else
            {
                if (!IsRecording || activeCapture is null)
                {
                    return Task.CompletedTask;
                }

                activeCapture.StopRecording();
                return stopCompletionSource?.Task ?? Task.CompletedTask;
            }
        }

        return StopMixedAsync(mixed);
    }

    private async Task StopMixedAsync(MixedAudioRecording mixed)
    {
        try
        {
            await mixed.StopAsync().ConfigureAwait(false);
        }
        finally
        {
            lock (syncRoot)
            {
                mixed.Dispose();
                IsRecording = false;
            }
        }
    }

    private static IWaveIn CreateCapture(AudioRecordingRequest request)
    {
        return request.Source switch
        {
            AudioRecordingSource.Microphone => CreateMicrophoneCapture(request),
            AudioRecordingSource.SystemAudio => new WasapiLoopbackCapture(),
            // MicrophoneAndSystemAudio is handled by MixedAudioRecording in StartAsync.
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

            mixedRecording?.Dispose();
            mixedRecording = null;

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
