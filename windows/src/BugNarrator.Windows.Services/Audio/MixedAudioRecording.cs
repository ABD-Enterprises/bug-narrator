using System.Diagnostics;
using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

/// <summary>
/// Captures the microphone and system-audio loopback simultaneously and writes a single mixed
/// 16 kHz mono 16-bit PCM WAV. The two captures fill independent buffers; a pump thread reads the
/// mixed pipeline paced to the wall clock so the sources stay aligned without progressive drift.
/// </summary>
internal sealed class MixedAudioRecording : IDisposable
{
    private const int PumpIntervalMilliseconds = 20;
    private const int OutputBytesPerSample = 2; // 16-bit mono

    private readonly object writeLock = new();
    private readonly WaveInEvent microphoneCapture;
    private readonly WasapiLoopbackCapture systemCapture;
    private readonly BufferedWaveProvider microphoneBuffer;
    private readonly BufferedWaveProvider systemBuffer;
    private readonly IWaveProvider mixedOutput;
    private readonly WaveFileWriter writer;
    private readonly Stopwatch clock = new();
    private readonly byte[] pumpBuffer = new byte[16384];

    private Thread? pumpThread;
    private volatile bool running;
    private long bytesWritten;
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
        running = true;
        clock.Start();

        try
        {
            microphoneCapture.StartRecording();
            systemCapture.StartRecording();
        }
        catch
        {
            running = false;
            throw;
        }

        pumpThread = new Thread(PumpLoop)
        {
            IsBackground = true,
            Name = "BugNarrator.MixedAudioPump",
        };
        pumpThread.Start();
    }

    public Task StopAsync()
    {
        return Task.Run(Stop);
    }

    private void Stop()
    {
        running = false;
        pumpThread?.Join(TimeSpan.FromSeconds(5));
        pumpThread = null;
        clock.Stop();

        TryStop(microphoneCapture);
        TryStop(systemCapture);

        // Final drain so the output length matches the elapsed wall-clock time.
        DrainToClock();

        lock (writeLock)
        {
            writer.Flush();
        }

        if (captureFailure is { } failure)
        {
            throw failure;
        }
    }

    private void PumpLoop()
    {
        while (running)
        {
            DrainToClock();
            Thread.Sleep(PumpIntervalMilliseconds);
        }
    }

    private void DrainToClock()
    {
        // Pace output to real time: the number of bytes that should exist by now is
        // elapsed seconds * sample rate * bytes/sample. Writing only the delta each tick keeps
        // both sources locked to the wall clock and prevents progressive drift, while the mixer's
        // ReadFully fills any momentary gap in a single source with silence.
        var targetBytes =
            (long)(clock.Elapsed.TotalSeconds * MixedAudioPipeline.TargetSampleRate) * OutputBytesPerSample;

        lock (writeLock)
        {
            var pending = targetBytes - bytesWritten;
            while (pending > 0)
            {
                var want = (int)Math.Min(pumpBuffer.Length, pending);
                var read = mixedOutput.Read(pumpBuffer, 0, want);
                if (read <= 0)
                {
                    break;
                }

                writer.Write(pumpBuffer, 0, read);
                bytesWritten += read;
                pending -= read;
            }
        }
    }

    private void OnMicrophoneDataAvailable(object? sender, WaveInEventArgs eventArgs)
    {
        microphoneBuffer.AddSamples(eventArgs.Buffer, 0, eventArgs.BytesRecorded);
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
        running = false;
        pumpThread?.Join(TimeSpan.FromSeconds(5));
        pumpThread = null;

        microphoneCapture.DataAvailable -= OnMicrophoneDataAvailable;
        systemCapture.DataAvailable -= OnSystemDataAvailable;
        microphoneCapture.RecordingStopped -= OnCaptureStopped;
        systemCapture.RecordingStopped -= OnCaptureStopped;

        microphoneCapture.Dispose();
        systemCapture.Dispose();
        writer.Dispose();
    }
}
