using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace BugNarrator.Windows.Services.Audio;

/// <summary>
/// Builds the deterministic mixing pipeline that converts a microphone stream and a system-audio
/// stream into a single 16 kHz mono 16-bit PCM stream. Kept free of capture devices so it can be
/// unit-tested with synthetic sample providers.
/// </summary>
public static class MixedAudioPipeline
{
    /// <summary>
    /// Target sample rate for mixed output. Matches the microphone capture format and is the rate
    /// transcription downsamples to anyway, which keeps mixed recordings small and consistent.
    /// </summary>
    public const int TargetSampleRate = 16000;

    /// <summary>
    /// Mixes the two sources into one 16 kHz mono 16-bit PCM wave provider. Both sources are
    /// downmixed to mono and resampled to <see cref="TargetSampleRate"/> before being summed.
    /// </summary>
    public static IWaveProvider Create(ISampleProvider microphone, ISampleProvider systemAudio)
    {
        ArgumentNullException.ThrowIfNull(microphone);
        ArgumentNullException.ThrowIfNull(systemAudio);

        var mixer = new MixingSampleProvider(WaveFormat.CreateIeeeFloatWaveFormat(TargetSampleRate, 1))
        {
            // Keep emitting a continuous timeline even when one source momentarily has no data
            // (for example, system audio while nothing is playing); missing input becomes silence.
            ReadFully = true,
        };

        mixer.AddMixerInput(ToMonoTargetRate(microphone));
        mixer.AddMixerInput(ToMonoTargetRate(systemAudio));

        return new SampleToWaveProvider16(mixer);
    }

    /// <summary>
    /// Converts a source to mono at <see cref="TargetSampleRate"/> so it can feed the mixer.
    /// </summary>
    public static ISampleProvider ToMonoTargetRate(ISampleProvider source)
    {
        ArgumentNullException.ThrowIfNull(source);

        var mono = source.WaveFormat.Channels == 1
            ? source
            : new MonoDownmixSampleProvider(source);

        return mono.WaveFormat.SampleRate == TargetSampleRate
            ? mono
            : new WdlResamplingSampleProvider(mono, TargetSampleRate);
    }
}
