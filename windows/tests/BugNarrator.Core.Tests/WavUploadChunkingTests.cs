using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

/// <summary>
/// Plan cases are ported from Tests/BugNarratorTests/TranscriptionChunkerTests.swift (in frames);
/// the WAV cutter is exercised on a real generated file (#1202).
/// </summary>
public sealed class WavUploadChunkingTests
{
    private const int Rate = 16_000;
    private static readonly TimeSpan Max = TimeSpan.FromSeconds(480);
    private static readonly TimeSpan MinTail = TimeSpan.FromSeconds(1);

    private static IReadOnlyList<WavUploadChunking.Span> Plan(double seconds, TimeSpan? max = null, TimeSpan? minTail = null) =>
        WavUploadChunking.Plan((long)(seconds * Rate), Rate, max ?? Max, minTail ?? MinTail);

    private static long F(double seconds) => (long)(seconds * Rate);

    // MARK: plan

    [Fact] public void ShorterThanMax_IsNotChunked() => Assert.Empty(Plan(120));
    [Fact] public void ExactlyMax_IsNotChunked() => Assert.Empty(Plan(480));
    [Fact] public void ZeroOrNegative_IsNotChunked() { Assert.Empty(Plan(0)); Assert.Empty(WavUploadChunking.Plan(-5, Rate)); Assert.Empty(WavUploadChunking.Plan(F(1000), 0)); Assert.Empty(Plan(0.5, TimeSpan.Zero)); }

    [Fact]
    public void TwoAndAHalfChunks()
    {
        Assert.Equal([new(0, F(480)), new(F(480), F(480)), new(F(960), F(240))], Plan(1200));
    }

    [Fact]
    public void SubThresholdTail_IsFoldedIntoThePreviousChunk()
    {
        // 8:00.5 used to yield a half-second second chunk on macOS (#1098).
        Assert.Equal([new(0, F(480.5))], Plan(480.5));
        Assert.Equal([new(0, F(480)), new(F(480), F(480.9))], Plan(960.9));
    }

    [Fact]
    public void TailAtThreshold_IsItsOwnChunk() => Assert.Equal([new(0, F(480)), new(F(480), F(1))], Plan(481));

    [Fact]
    public void ExactMultiple_HasNoEmptyTail() => Assert.Equal(2, Plan(960).Count);

    [Fact]
    public void SpansAreContiguousAndCoverTheWholeRecording()
    {
        foreach (var seconds in new[] { 481, 700, 1000, 1439.99, 3600 })
        {
            var spans = Plan(seconds);
            long next = 0;
            foreach (var span in spans) { Assert.Equal(next, span.StartFrame); Assert.True(span.FrameCount > 0); next += span.FrameCount; }
            Assert.Equal(F(seconds), next);
        }
    }

    // MARK: WAV cutting

    private static byte[] MakeWav(int frames, short channels = 1, short bits = 16, int rate = Rate, Func<int, short>? sample = null)
    {
        var bytesPerFrame = channels * bits / 8;
        var data = new byte[frames * bytesPerFrame];
        for (var i = 0; i < frames; i++)
        {
            var v = BitConverter.GetBytes(sample?.Invoke(i) ?? (short)(i % 32768));
            for (var c = 0; c < channels; c++) { data[(i * bytesPerFrame) + (c * 2)] = v[0]; data[(i * bytesPerFrame) + (c * 2) + 1] = v[1]; }
        }

        using var ms = new MemoryStream();
        void W(byte[] b) => ms.Write(b, 0, b.Length);
        W("RIFF"u8.ToArray()); W(BitConverter.GetBytes((uint)(36 + data.Length))); W("WAVE"u8.ToArray());
        W("fmt "u8.ToArray()); W(BitConverter.GetBytes(16u)); W(BitConverter.GetBytes((ushort)1)); W(BitConverter.GetBytes((ushort)channels));
        W(BitConverter.GetBytes((uint)rate)); W(BitConverter.GetBytes((uint)(rate * bytesPerFrame))); W(BitConverter.GetBytes((ushort)bytesPerFrame)); W(BitConverter.GetBytes((ushort)bits));
        W("data"u8.ToArray()); W(BitConverter.GetBytes((uint)data.Length)); W(data);
        return ms.ToArray();
    }

    [Fact]
    public void ReadLayout_ParsesTheCanonicalHeader()
    {
        using var wav = new MemoryStream(MakeWav(100));
        var layout = WavUploadChunking.ReadLayout(wav);
        Assert.Equal(new WavUploadChunking.PcmLayout(Rate, 1, 16, 44, 200), layout);
        Assert.Equal(100, layout.FrameCount);
    }

    [Fact]
    public void ReadLayout_SkipsAForeignChunkBeforeData()
    {
        var canonical = MakeWav(10);
        // Insert a LIST chunk (odd-sized, so padding is exercised) between fmt and data.
        var list = new List<byte>(canonical[..36]);
        list.AddRange("LIST"u8.ToArray()); list.AddRange(BitConverter.GetBytes(3u)); list.AddRange(new byte[] { 1, 2, 3, 0 });
        list.AddRange(canonical[36..]);
        using var wav = new MemoryStream(list.ToArray());
        var layout = WavUploadChunking.ReadLayout(wav);
        Assert.Equal(44 + 12, layout.DataOffset);
        Assert.Equal(10, layout.FrameCount);
    }

    [Fact]
    public void ReadLayout_TrustsTheFileOverAnOversizedDataHeader()
    {
        var bytes = MakeWav(10);
        BitConverter.GetBytes(uint.MaxValue).CopyTo(bytes, 40); // data size claims 4 GB
        using var wav = new MemoryStream(bytes);
        Assert.Equal(10, WavUploadChunking.ReadLayout(wav).FrameCount);
    }

    [Theory]
    [InlineData("RIFX")]
    [InlineData("OggS")]
    public void ReadLayout_RejectsNonWave(string magic)
    {
        var bytes = MakeWav(10); System.Text.Encoding.ASCII.GetBytes(magic).CopyTo(bytes, 0);
        Assert.Throws<InvalidDataException>(() => WavUploadChunking.ReadLayout(new MemoryStream(bytes)));
    }

    [Fact]
    public void ReadLayout_RejectsFloatPcm()
    {
        var bytes = MakeWav(10); BitConverter.GetBytes((ushort)3).CopyTo(bytes, 20);
        Assert.Throws<InvalidDataException>(() => WavUploadChunking.ReadLayout(new MemoryStream(bytes)));
    }

    [Fact]
    public void WriteChunk_ProducesAStandaloneWavWithExactlyTheSpansFrames()
    {
        var source = MakeWav(1000, sample: i => (short)i);
        using var sourceStream = new MemoryStream(source);
        var layout = WavUploadChunking.ReadLayout(sourceStream);
        using var chunk = new MemoryStream();

        WavUploadChunking.WriteChunk(sourceStream, layout, new WavUploadChunking.Span(300, 200), chunk);

        chunk.Position = 0;
        var chunkLayout = WavUploadChunking.ReadLayout(chunk);
        Assert.Equal(200, chunkLayout.FrameCount);
        Assert.Equal(layout with { DataOffset = 44, DataLength = 400 }, chunkLayout);
        Assert.Equal(44 + 400, chunk.Length);
        var bytes = chunk.ToArray();
        Assert.Equal(300, BitConverter.ToInt16(bytes, 44));            // first frame is frame 300
        Assert.Equal(499, BitConverter.ToInt16(bytes, 44 + 398));      // last frame is frame 499
        // The exact 44-byte header a strict decoder reads: RIFF size, byte rate, block align.
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(bytes, 0, 4));
        Assert.Equal(36u + 400, BitConverter.ToUInt32(bytes, 4));
        Assert.Equal("WAVEfmt ", System.Text.Encoding.ASCII.GetString(bytes, 8, 8));
        Assert.Equal(16u, BitConverter.ToUInt32(bytes, 16));
        Assert.Equal(1, BitConverter.ToUInt16(bytes, 20));
        Assert.Equal(1, BitConverter.ToUInt16(bytes, 22));
        Assert.Equal((uint)Rate, BitConverter.ToUInt32(bytes, 24));
        Assert.Equal((uint)(Rate * 2), BitConverter.ToUInt32(bytes, 28));
        Assert.Equal(2, BitConverter.ToUInt16(bytes, 32));
        Assert.Equal(16, BitConverter.ToUInt16(bytes, 34));
        Assert.Equal("data", System.Text.Encoding.ASCII.GetString(bytes, 36, 4));
        Assert.Equal(400u, BitConverter.ToUInt32(bytes, 40));
    }

    [Fact]
    public void ReadLayout_AcceptsTheEighteenByteFmtNAudioWrites()
    {
        // NAudio's WaveFileWriter emits WAVEFORMATEX with cbSize (fmt size 18), not the 16-byte form.
        var canonical = MakeWav(10);
        var bytes = new List<byte>(canonical[..16]);
        bytes.AddRange(BitConverter.GetBytes(18u)); bytes.AddRange(canonical[20..36]); bytes.AddRange(new byte[] { 0, 0 });
        bytes.AddRange(canonical[36..]);
        using var wav = new MemoryStream(bytes.ToArray());
        var layout = WavUploadChunking.ReadLayout(wav);
        Assert.Equal(46, layout.DataOffset);
        Assert.Equal(10, layout.FrameCount);
    }

    [Theory]
    [InlineData(8u)]
    [InlineData(0x7FFFFFFFu)]
    public void ReadLayout_RejectsAnImplausibleFmtSizeInsteadOfAllocatingIt(uint size)
    {
        var bytes = MakeWav(10); BitConverter.GetBytes(size).CopyTo(bytes, 16);
        Assert.Throws<InvalidDataException>(() => WavUploadChunking.ReadLayout(new MemoryStream(bytes)));
    }

    [Fact]
    public void WriteChunk_RefusesAChunkThatWouldExceedTheUploadLimit()
    {
        // A denser layout than the recorder's: 96 kHz stereo 24-bit, 8 minutes = 276 MB.
        var layout = new WavUploadChunking.PcmLayout(96_000, 2, 24, 44, 0);
        var span = new WavUploadChunking.Span(0, 8 * 60 * 96_000L);
        Assert.Throws<InvalidDataException>(() => WavUploadChunking.WriteChunk(new MemoryStream(new byte[44]), layout, span, new MemoryStream()));
    }

    [Fact]
    public void CuttingAlongThePlan_ReassemblesTheOriginalSamples()
    {
        const int frames = 1000;
        var source = MakeWav(frames, sample: i => (short)(i * 7));
        using var sourceStream = new MemoryStream(source);
        var layout = WavUploadChunking.ReadLayout(sourceStream);
        var spans = WavUploadChunking.Plan(frames, Rate, TimeSpan.FromSeconds(0.025), TimeSpan.FromSeconds(0.001)); // 400-frame chunks

        var reassembled = new List<byte>();
        foreach (var span in spans)
        {
            using var chunk = new MemoryStream();
            WavUploadChunking.WriteChunk(sourceStream, layout, span, chunk);
            reassembled.AddRange(chunk.ToArray()[44..]);
        }

        Assert.Equal(3, spans.Count);
        Assert.Equal(source[44..], reassembled.ToArray());
    }

    [Fact]
    public void WriteChunk_StereoKeepsBothChannels()
    {
        var source = MakeWav(50, channels: 2);
        using var sourceStream = new MemoryStream(source);
        var layout = WavUploadChunking.ReadLayout(sourceStream);
        Assert.Equal(4, layout.BytesPerFrame);
        using var chunk = new MemoryStream();
        WavUploadChunking.WriteChunk(sourceStream, layout, new WavUploadChunking.Span(10, 5), chunk);
        Assert.Equal(44 + 20, chunk.Length);
    }

    [Fact]
    public void WriteChunk_ThrowsWhenTheFileEndsEarly()
    {
        using var sourceStream = new MemoryStream(MakeWav(10));
        var layout = WavUploadChunking.ReadLayout(sourceStream);
        Assert.Throws<InvalidDataException>(() => WavUploadChunking.WriteChunk(sourceStream, layout, new WavUploadChunking.Span(5, 50), new MemoryStream()));
    }

    [Fact]
    public void EightMinutesOfSixteenKilohertzMono_StaysUnderTheUploadCeiling()
    {
        var bytes = 44 + (WavUploadChunking.MaximumChunkDuration.TotalSeconds * Rate * 2);
        Assert.True(bytes < WavUploadChunking.MaximumSingleUploadBytes, $"{bytes} bytes");
        Assert.Equal(15_360_044, bytes);
    }
}
