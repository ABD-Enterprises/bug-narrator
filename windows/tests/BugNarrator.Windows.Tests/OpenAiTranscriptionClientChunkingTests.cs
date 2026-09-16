using System.Net;
using System.Net.Http;
using System.Text;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Transcription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>Long-recording upload chunking (#1202). The planner and cutter are pinned in Core.Tests; this drives the HTTP path.</summary>
public sealed class OpenAiTranscriptionClientChunkingTests : IDisposable
{
    private readonly string directory = Path.Combine(Path.GetTempPath(), "bug-narrator-chunk-tests-" + Guid.NewGuid().ToString("N"));

    public OpenAiTranscriptionClientChunkingTests() => Directory.CreateDirectory(directory);

    public void Dispose() { try { Directory.Delete(directory, recursive: true); } catch { } }

    private string WriteWav(int seconds, string name = "recording.wav")
    {
        const int rate = 16_000;
        var data = new byte[seconds * rate * 2];
        var path = Path.Combine(directory, name);
        using var stream = File.Create(path);
        void W(byte[] b) => stream.Write(b, 0, b.Length);
        W("RIFF"u8.ToArray()); W(BitConverter.GetBytes((uint)(36 + data.Length))); W("WAVE"u8.ToArray());
        W("fmt "u8.ToArray()); W(BitConverter.GetBytes(16u)); W(BitConverter.GetBytes((ushort)1)); W(BitConverter.GetBytes((ushort)1));
        W(BitConverter.GetBytes((uint)rate)); W(BitConverter.GetBytes((uint)(rate * 2))); W(BitConverter.GetBytes((ushort)2)); W(BitConverter.GetBytes((ushort)16));
        W("data"u8.ToArray()); W(BitConverter.GetBytes((uint)data.Length)); W(data);
        return path;
    }

    private static OpenAiTranscriptionClient Client(Func<HttpRequestMessage, Task<HttpResponseMessage>> respond) =>
        new(new HttpClient(new TestHttpMessageHandler((request, _) => respond(request))));

    private static OpenAiTranscriptionRequest Request() => new("whisper-1", null, null, null);

    [Fact]
    public async Task OverLimitWav_IsUploadedInChunksAndTheTextsAreJoined()
    {
        var path = WriteWav(14 * 60); // 26.9 MB, over the 24 MiB gate; two 8-minute-bounded spans (8:00 + 6:00)
        var uploads = new List<long>();
        var client = Client(async request =>
        {
            var multipart = Assert.IsType<MultipartFormDataContent>(request.Content);
            var file = multipart.First(part => part.Headers.ContentDisposition?.Name?.Trim('"') == "file");
            uploads.Add((await file.ReadAsByteArrayAsync()).LongLength);
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent($"{{\"text\":\"Chunk {uploads.Count} transcript\"}}", Encoding.UTF8, "application/json"),
            };
        });

        var transcript = await client.TranscribeToTextAsync(path, "fixture-key", Request());

        Assert.Equal("Chunk 1 transcript\n\nChunk 2 transcript", transcript);
        Assert.Equal(2, uploads.Count);
        Assert.Equal(44 + (8 * 60 * 16_000 * 2), uploads[0]);
        Assert.Equal(44 + (6 * 60 * 16_000 * 2), uploads[1]);
        Assert.All(uploads, size => Assert.True(size < WavUploadChunking.MaximumSingleUploadBytes));
        Assert.Empty(Directory.GetDirectories(Path.GetTempPath(), "BugNarrator-Chunks-*"));
    }

    [Fact]
    public async Task UnderLimitWav_IsUploadedWhole()
    {
        var path = WriteWav(60);
        var uploads = 0;
        var client = Client(_ =>
        {
            uploads++;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("{\"text\":\"whole\"}", Encoding.UTF8, "application/json"),
            });
        });

        Assert.Equal("whole", await client.TranscribeToTextAsync(path, "fixture-key", Request()));
        Assert.Equal(1, uploads);
    }

    [Fact]
    public async Task OverLimitNonWav_IsRefusedBeforeAnyUpload()
    {
        var path = Path.Combine(directory, "big.m4a");
        using (var stream = File.Create(path)) { stream.SetLength(WavUploadChunking.MaximumSingleUploadBytes + 1); }
        var client = Client(_ => throw new InvalidOperationException("the network must not be called"));

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => client.TranscribeToTextAsync(path, "fixture-key", Request()));
        Assert.Contains("safe upload limit", error.Message);
    }

    [Fact]
    public async Task AFailingChunk_PropagatesTheProviderMessageAndCleansUp()
    {
        var path = WriteWav(14 * 60);
        var client = Client(_ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests)
        {
            Content = new StringContent("{\"error\":{\"message\":\"Rate limit reached\"}}", Encoding.UTF8, "application/json"),
        }));

        var error = await Assert.ThrowsAsync<InvalidOperationException>(() => client.TranscribeToTextAsync(path, "fixture-key", Request()));
        Assert.Contains("Rate limit reached", error.Message);
        Assert.Empty(Directory.GetDirectories(Path.GetTempPath(), "BugNarrator-Chunks-*"));
    }
}
