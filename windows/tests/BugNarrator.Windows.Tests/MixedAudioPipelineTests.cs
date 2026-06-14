using BugNarrator.Windows.Services.Audio;
using NAudio.Wave;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class MixedAudioPipelineTests
{
    [Fact]
    public void Create_ProducesMono16BitPcmAtTargetRate()
    {
        var output = MixedAudioPipeline.Create(
            MonoFloat(MixedAudioPipeline.TargetSampleRate, 0f),
            MonoFloat(MixedAudioPipeline.TargetSampleRate, 0f));

        Assert.Equal(MixedAudioPipeline.TargetSampleRate, output.WaveFormat.SampleRate);
        Assert.Equal(1, output.WaveFormat.Channels);
        Assert.Equal(16, output.WaveFormat.BitsPerSample);
        Assert.Equal(WaveFormatEncoding.Pcm, output.WaveFormat.Encoding);
    }

    [Fact]
    public void Create_SumsBothSources()
    {
        // 0.25 + 0.25 = 0.5 of full scale -> ~16383 as a signed 16-bit sample.
        var output = MixedAudioPipeline.Create(
            MonoFloat(MixedAudioPipeline.TargetSampleRate, 0.25f),
            MonoFloat(MixedAudioPipeline.TargetSampleRate, 0.25f));

        var sample = ReadSteadyStateSample(output);

        Assert.InRange(sample, 16383 - 4, 16383 + 4);
    }

    [Fact]
    public void Create_ResamplesAndDownmixesSystemAudioToTargetRate()
    {
        // Microphone silent; system audio is 48 kHz stereo at 0.5 full scale on both channels.
        // After downmix (0.5) and resample to 16 kHz the steady-state value should be ~0.5.
        var output = MixedAudioPipeline.Create(
            MonoFloat(MixedAudioPipeline.TargetSampleRate, 0f),
            StereoFloat(48000, 0.5f, 0.5f));

        var sample = ReadSteadyStateSample(output);

        Assert.InRange(sample, 16383 - 96, 16383 + 96);
    }

    [Fact]
    public void MonoDownmix_AveragesChannels()
    {
        var downmix = new MonoDownmixSampleProvider(StereoFloat(MixedAudioPipeline.TargetSampleRate, 0.2f, 0.6f));

        Assert.Equal(1, downmix.WaveFormat.Channels);

        var buffer = new float[64];
        var read = downmix.Read(buffer, 0, buffer.Length);

        Assert.Equal(buffer.Length, read);
        Assert.All(buffer, value => Assert.Equal(0.4f, value, precision: 4));
    }

    private static short ReadSteadyStateSample(IWaveProvider output)
    {
        // Read ~0.5s so any resampler warm-up has passed, then sample near the end.
        var bytes = new byte[MixedAudioPipeline.TargetSampleRate]; // 8000 samples * 2 bytes
        var total = 0;
        while (total < bytes.Length)
        {
            var read = output.Read(bytes, total, bytes.Length - total);
            if (read <= 0)
            {
                break;
            }

            total += read;
        }

        var lastSampleIndex = bytes.Length - 2;
        return BitConverter.ToInt16(bytes, lastSampleIndex);
    }

    private static ISampleProvider MonoFloat(int sampleRate, float value)
    {
        return new ConstantSampleProvider(WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, 1), value, value);
    }

    private static ISampleProvider StereoFloat(int sampleRate, float left, float right)
    {
        return new ConstantSampleProvider(WaveFormat.CreateIeeeFloatWaveFormat(sampleRate, 2), left, right);
    }

    private sealed class ConstantSampleProvider : ISampleProvider
    {
        private readonly float[] channelValues;

        public ConstantSampleProvider(WaveFormat waveFormat, params float[] channelValues)
        {
            WaveFormat = waveFormat;
            this.channelValues = channelValues;
        }

        public WaveFormat WaveFormat { get; }

        public int Read(float[] buffer, int offset, int count)
        {
            for (var i = 0; i < count; i++)
            {
                buffer[offset + i] = channelValues[i % WaveFormat.Channels];
            }

            return count;
        }
    }
}
