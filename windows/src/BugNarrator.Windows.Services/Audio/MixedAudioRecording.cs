using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

/// <summary>
/// Captures the microphone and system-audio loopback simultaneously and writes a single mixed
/// 16 kHz mono 16-bit PCM WAV. Driving the mixing directly from the microphone's DataAvailable
/// event keeps the two sources aligned and paced to the microphone's clock.
/// </summary>
internal sealed class MixedAudioRecording : IDisposable
{
    private readonly object writeLock = new();
    private readonly WaveInEvent microphoneCapture;
    private readonly WasapiLoopbackCapture systemCapture;
    private readonly BufferedWaveProvider microphoneBuffer;
    private readonly BufferedWaveProvider systemBuffer;
    private readonly IWaveProvider mixedOutput;
    private readonly WaveFileWriter writer;
    private readonly byte[] mixBuffer = new byte[16384];

    private Exception? captureFailure;

    public MixedAudioRecording(string audioFilePath, int microphoneDeviceNumber)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(audioFilePath)!);

        microphoneCapture = new WaveInEvent
        {
            BufferMilliseconds = 125,
            DeviceNumber = microphoneDeviceNumber,
            WaveFormat = new WaveFormat(MixedAudioPipeline.TargetSampleRate, 16, 1),
        };
        systemCapture = new WasapiLoopbackCapture();

        microphoneBuffer = new BufferedWaveProvider(microphoneCapture.WaveFormat)
        {
            DiscardOnBufferOverflow = true,
            BufferDuration = TimeSpan.FromSeconds(10),
        };
        systemBuffer = new BufferedWaveProvider(systemCapture.WaveFormat)
        {
            DiscardOnBufferOverflow = true,
            BufferDuration = TimeSpan.FromSeconds(10),
        };

        mixedOutput = MixedAudioPipeline.Create(
            microphoneBuffer.ToSampleProvider(),
            systemBuffer.ToSampleProvider());

        writer = new WaveFileWriter(audioFilePath, mixedOutput.WaveFormat);

        microphoneCapture.DataAvailable += OnMicrophoneDataAvailable;
        systemCapture.DataAvailable += OnSystemDataAvailable;
        microphoneCapture.RecordingStopped += OnCaptureStopped;
        systemCapture.RecordingStopped += OnCaptureStopped;
    }

    public void Start()
    {
        microphoneCapture.StartRecording();
        systemCapture.StartRecording();
    }

    public Task StopAsync()
    {
        return Task.Run(Stop);
    }

    private void Stop()
    {
        TryStop(microphoneCapture);
        TryStop(systemCapture);

        lock (writeLock)
        {
            writer.Flush();
        }

        if (captureFailure is { } failure)
        {
            throw failure;
        }
    }

    private void OnMicrophoneDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        lock (writeLock)
        {
            microphoneBuffer.AddSamples(eventArgs.Buffer, 0, eventArgs.BytesRecorded);

            var pending = eventArgs.BytesRecorded;
            while (pending > 0)
            {
                var want = Math.Min(mixBuffer.Length, pending);
                var read = mixedOutput.Read(mixBuffer, 0, want);
                if (read <= 0)
                {
                    break;
                }

                writer.Write(mixBuffer, 0, read);
                pending -= read;
            }
        }
    }

    private void OnSystemDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        systemBuffer.AddSamples(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
    }

    private void OnCaptureStopped(object? sender, StoppedEventArgs eventArgs)
    {
        if (eventArgs.Exception is not null)
        {
            captureFailure ??= eventArgs.Exception;
        }
    }

    private static void TryStop(IWaveIn capture)
    {
        try
        {
            capture.StopRecording();
        }
        catch
        {
            // Stopping a capture that already faulted should not mask the original failure.
        }
    }

    public void Dispose()
    {
        microphoneCapture.DataAvailable -= OnMicrophoneDataAvailable;
        systemCapture.DataAvailable -= OnSystemDataAvailable;
        microphoneCapture.RecordingStopped -= OnCaptureStopped;
        systemCapture.RecordingStopped -= OnCaptureStopped;

        microphoneCapture.Dispose();
        systemCapture.Dispose();
        writer.Dispose();
    }
}
