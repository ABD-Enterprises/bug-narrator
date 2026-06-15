using NAudio.Wave;

namespace BugNarrator.Windows.Services.Audio;

/// <summary>
/// Averages every channel of the source into a single mono channel. Used so a stereo (or
/// multi-channel) system-audio loopback stream can be mixed against the mono microphone stream.
/// </summary>
public sealed class MonoDownmixSampleProvider : ISampleProvider
{
    private readonly ISampleProvider source;
    private readonly int sourceChannels;
    private float[] sourceBuffer = [];

    public MonoDownmixSampleProvider(ISampleProvider source)
    {
        ArgumentNullException.ThrowIfNull(source);

        this.source = source;
        sourceChannels = source.WaveFormat.Channels;
        WaveFormat = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
    }

    public WaveFormat WaveFormat { get; }

    public int Read(float[] buffer, int offset, int count)
    {
        if (sourceChannels == 1)
        {
            return source.Read(buffer, offset, count);
        }

        var requiredSourceSamples = count * sourceChannels;
        if (sourceBuffer.Length < requiredSourceSamples)
        {
            sourceBuffer = new float[requiredSourceSamples];
        }

        var samplesRead = source.Read(sourceBuffer, 0, requiredSourceSamples);
        var framesRead = samplesRead / sourceChannels;

        for (var frame = 0; frame < framesRead; frame++)
        {
            var sum = 0f;
            for (var channel = 0; channel < sourceChannels; channel++)
            {
                sum += sourceBuffer[(frame * sourceChannels) + channel];
            }

            buffer[offset + frame] = sum / sourceChannels;
        }

        return framesRead;
    }
}
