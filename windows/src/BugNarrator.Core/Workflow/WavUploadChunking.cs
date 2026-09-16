namespace BugNarrator.Core.Workflow;

/// <summary>
/// The pure part of long-recording transcription on Windows (#1202), mirroring macOS
/// <c>DefaultTranscriptionChunker.plan</c>: decide the spans, then cut a PCM WAV into
/// self-contained WAV files along them. Windows records 16 kHz 16-bit mono PCM (1.92 MB/min);
/// the transcription endpoint rejects uploads over 25 MB, so a recording past ~13 minutes has
/// to travel in pieces. Whisper resamples to 16 kHz internally, so cutting the PCM loses nothing
/// and needs no codec (committee decision on #1202).
/// </summary>
public static class WavUploadChunking
{
    /// <summary>Uploads this large or larger are split (the macOS <c>AudioUploadPolicy</c> figure).</summary>
    public const long MaximumSingleUploadBytes = 24L * 1024 * 1024;

    /// <summary>Upper bound per chunk; 8 minutes of 16 kHz mono PCM is 15.36 MB.</summary>
    public static readonly TimeSpan MaximumChunkDuration = TimeSpan.FromMinutes(8);

    /// <summary>A final slice shorter than this is folded into the previous chunk (macOS #1098).</summary>
    public static readonly TimeSpan MinimumTailDuration = TimeSpan.FromSeconds(1);

    /// <summary>One planned slice, in sample frames from the start of the recording.</summary>
    public readonly record struct Span(long StartFrame, long FrameCount);

    /// <summary>The PCM layout a WAV declares, plus where its samples live in the file.</summary>
    public readonly record struct PcmLayout(int SampleRate, short Channels, short BitsPerSample, long DataOffset, long DataLength)
    {
        public int BytesPerFrame => Channels * (BitsPerSample / 8);
        public long FrameCount => BytesPerFrame == 0 ? 0 : DataLength / BytesPerFrame;
    }

    /// <summary>
    /// Plans spans for <paramref name="totalFrames"/> at <paramref name="sampleRate"/>. Empty
    /// means "send the file whole": the recording is within one chunk's duration. A sub-threshold
    /// tail is absorbed into the previous chunk rather than uploaded on its own.
    /// </summary>
    public static IReadOnlyList<Span> Plan(long totalFrames, int sampleRate, TimeSpan? maxChunkDuration = null, TimeSpan? minimumTailDuration = null)
    {
        if (totalFrames <= 0 || sampleRate <= 0)
        {
            return Array.Empty<Span>();
        }

        var maxFrames = (long)((maxChunkDuration ?? MaximumChunkDuration).TotalSeconds * sampleRate);
        var minTailFrames = (long)((minimumTailDuration ?? MinimumTailDuration).TotalSeconds * sampleRate);
        if (maxFrames <= 0 || totalFrames <= maxFrames)
        {
            return Array.Empty<Span>();
        }

        var spans = new List<Span>();
        long start = 0;
        while (start < totalFrames)
        {
            var remaining = totalFrames - start;
            var count = Math.Min(maxFrames, remaining);
            var tailAfterThis = remaining - count;
            if (tailAfterThis > 0 && tailAfterThis < minTailFrames)
            {
                count = remaining;
            }

            spans.Add(new Span(start, count));
            start += count;
        }

        return spans;
    }

    /// <summary>
    /// Reads the RIFF/WAVE header: walks the chunk list to the <c>fmt </c> and <c>data</c> chunks
    /// (NAudio's WaveFileWriter emits exactly those, but a LIST chunk from another writer is
    /// skipped rather than trusted). Only integer PCM is accepted.
    /// </summary>
    public static PcmLayout ReadLayout(Stream wav)
    {
        var header = new byte[12];
        ReadExactly(wav, header, "RIFF header");
        if (Ascii(header, 0) != "RIFF" || Ascii(header, 8) != "WAVE")
        {
            throw new InvalidDataException("The recorded audio file is not a RIFF/WAVE file.");
        }

        int? sampleRate = null; short? channels = null; short? bits = null;
        var chunkHeader = new byte[8];
        while (wav.Read(chunkHeader, 0, 8) == 8)
        {
            var id = Ascii(chunkHeader, 0);
            var size = BitConverter.ToUInt32(chunkHeader, 4);
            if (id == "fmt ")
            {
                // 16 for plain PCM, 18 with cbSize (what NAudio's WaveFileWriter emits), 40 for
                // WAVE_FORMAT_EXTENSIBLE; anything else is not a fmt chunk we understand, and
                // must not become a multi-gigabyte allocation from a hand-crafted header.
                if (size < 16 || size > 64)
                {
                    throw new InvalidDataException("The recorded audio file has an unexpected fmt chunk.");
                }

                var fmt = new byte[size];
                ReadExactly(wav, fmt, "fmt chunk");
                var format = BitConverter.ToInt16(fmt, 0);
                if (format != 1)
                {
                    throw new InvalidDataException("The recorded audio file is not integer PCM.");
                }

                channels = BitConverter.ToInt16(fmt, 2);
                sampleRate = BitConverter.ToInt32(fmt, 4);
                bits = BitConverter.ToInt16(fmt, 14);
                if (size % 2 == 1) { wav.Seek(1, SeekOrigin.Current); }
                continue;
            }

            if (id == "data")
            {
                if (sampleRate is null || channels is null || bits is null)
                {
                    throw new InvalidDataException("The recorded audio file has no fmt chunk before its data.");
                }

                // A writer that died mid-recording can leave a data size larger than the file;
                // trust the file, not the header.
                var available = wav.Length - wav.Position;
                var dataLength = Math.Min((long)size, available);
                return new PcmLayout(sampleRate.Value, channels.Value, bits.Value, wav.Position, dataLength);
            }

            wav.Seek(size + (size % 2), SeekOrigin.Current);
        }

        throw new InvalidDataException("The recorded audio file has no data chunk.");
    }

    /// <summary>
    /// Writes the frames of <paramref name="span"/> from <paramref name="source"/> as a complete
    /// 44-byte-header PCM WAV to <paramref name="destination"/>.
    /// </summary>
    public static void WriteChunk(Stream source, PcmLayout layout, Span span, Stream destination)
    {
        var bytesPerFrame = layout.BytesPerFrame;
        var byteCount = span.FrameCount * bytesPerFrame;
        // The plan is by duration, sized for the recorder's 16 kHz mono format. A denser layout
        // (this class does not know the recorder) could plan an 8-minute chunk far over the
        // endpoint limit; fail loudly rather than upload it.
        if (byteCount + 44 > MaximumSingleUploadBytes)
        {
            throw new InvalidDataException("A planned chunk exceeds the upload limit; the recording is not in the expected 16 kHz mono format.");
        }
        var byteRate = layout.SampleRate * bytesPerFrame;

        void Write(ReadOnlySpan<byte> bytes) => destination.Write(bytes);
        void Write32(uint value) => Write(BitConverter.GetBytes(value));
        void Write16(ushort value) => Write(BitConverter.GetBytes(value));

        Write("RIFF"u8); Write32((uint)(36 + byteCount)); Write("WAVE"u8);
        Write("fmt "u8); Write32(16); Write16(1);
        Write16((ushort)layout.Channels); Write32((uint)layout.SampleRate); Write32((uint)byteRate);
        Write16((ushort)bytesPerFrame); Write16((ushort)layout.BitsPerSample);
        Write("data"u8); Write32((uint)byteCount);

        source.Seek(layout.DataOffset + (span.StartFrame * bytesPerFrame), SeekOrigin.Begin);
        var buffer = new byte[1 << 16];
        var remaining = byteCount;
        while (remaining > 0)
        {
            var read = source.Read(buffer, 0, (int)Math.Min(buffer.Length, remaining));
            if (read <= 0)
            {
                throw new InvalidDataException("The recorded audio file ended before the planned chunk did.");
            }

            destination.Write(buffer, 0, read);
            remaining -= read;
        }
    }

    private static void ReadExactly(Stream stream, byte[] buffer, string what)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var read = stream.Read(buffer, offset, buffer.Length - offset);
            if (read <= 0)
            {
                throw new InvalidDataException($"The recorded audio file is truncated in its {what}.");
            }

            offset += read;
        }
    }

    private static string Ascii(byte[] bytes, int offset) => System.Text.Encoding.ASCII.GetString(bytes, offset, 4);
}
