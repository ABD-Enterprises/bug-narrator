using System.Net;
using System.Text;
using BugNarrator.Windows.Services.Http;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class ResponseBodyReaderTests
{
    [Fact]
    public async Task FailedResponseStopsReadingAtByteLimit()
    {
        var stream = new CountingStream(new byte[ResponseBodyReader.ErrorBodyByteLimit * 4]);
        using var response = new HttpResponseMessage(HttpStatusCode.BadRequest) { Content = new StreamContent(stream) };
        var text = await ResponseBodyReader.ReadAsync(response);
        Assert.Equal(ResponseBodyReader.ErrorBodyByteLimit, stream.BytesRead);
        Assert.Equal(ResponseBodyReader.ErrorBodyByteLimit, text.Length);
    }

    [Fact]
    public async Task SuccessfulResponseIsNotTruncated()
    {
        var expected = new string('a', ResponseBodyReader.ErrorBodyByteLimit + 10);
        using var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(expected) };
        Assert.Equal(expected, await ResponseBodyReader.ReadAsync(response));
    }

    [Fact]
    public async Task SuccessfulLengthlessResponseStopsAtTheStreamingCeiling()
    {
        var stream = new RepeatingStream();
        using var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) };
        await Assert.ThrowsAsync<InvalidOperationException>(() => ResponseBodyReader.ReadAsync(response));
        Assert.Equal(ResponseBodyReader.SuccessBodyByteLimit + 1, stream.BytesRead);
    }

    [Fact]
    public async Task SuccessfulDeclaredOversizeIsRefusedBeforeReading()
    {
        var stream = new RepeatingStream();
        using var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) };
        response.Content.Headers.ContentLength = ResponseBodyReader.SuccessBodyByteLimit + 1;
        await Assert.ThrowsAsync<InvalidOperationException>(() => ResponseBodyReader.ReadAsync(response));
        Assert.Equal(0, stream.BytesRead);
    }

    [Fact]
    public async Task SuccessfulResponsePreservesTheDeclaredCharset()
    {
        using var response = new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new StringContent("synthetic é fixture", Encoding.Unicode),
        };
        Assert.Equal("synthetic é fixture", await ResponseBodyReader.ReadAsync(response));
    }

    private sealed class RepeatingStream : Stream
    {
        public int BytesRead { get; private set; }
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => BytesRead; set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count)
        {
            Array.Fill(buffer, (byte)'x', offset, count);
            BytesRead += count;
            return count;
        }
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            buffer.Span.Fill((byte)'x');
            BytesRead += buffer.Length;
            return ValueTask.FromResult(buffer.Length);
        }
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    [Fact]
    public async Task HealthResponseUsesTheSameBoundEvenOnSuccess()
    {
        using var content = new StringContent(new string('a', ResponseBodyReader.ErrorBodyByteLimit + 10));
        Assert.Equal(ResponseBodyReader.ErrorBodyByteLimit, (await ResponseBodyReader.ReadBoundedAsync(content)).Length);
    }

    [Fact]
    public async Task CancelledReadIsNotReportedAsSuccess()
    {
        using var content = new StringContent("fixture");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            ResponseBodyReader.ReadBoundedAsync(content, cancellation.Token));
    }

    [Fact]
    public async Task InternalTimeoutIsReportedAsFailureInsteadOfUserCancellation()
    {
        using var response = new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StreamContent(new StalledStream(simulateTimeout: true)),
        };
        var failure = await Assert.ThrowsAsync<InvalidOperationException>(() => ResponseBodyReader.ReadAsync(response));
        Assert.Contains("timed out", failure.Message);
    }

    [Fact]
    public async Task CancellationWhileReadingRemainsUserCancellation()
    {
        using var response = new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StreamContent(new StalledStream(simulateTimeout: false)),
        };
        using var cancellation = new CancellationTokenSource();
        var reading = ResponseBodyReader.ReadAsync(response, cancellation.Token);
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => reading);
    }

    private sealed class StalledStream(bool simulateTimeout) : MemoryStream
    {
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            if (simulateTimeout) throw new OperationCanceledException();
            await Task.Delay(Timeout.Infinite, cancellationToken);
            return 0;
        }
    }

    [Fact]
    public void ErrorMessageCannotCreateLogLinesOrGrowWithoutLimit()
    {
        var input = "fixture\r\nforged\u001b[2J\u2028\u202e" + new string('x', 9000);
        var result = ResponseBodyReader.SanitizeMessage(input);
        Assert.Equal(ResponseBodyReader.MessageCharacterLimit, result.Length);
        Assert.DoesNotContain('\n', result);
        Assert.DoesNotContain('\r', result);
        Assert.DoesNotContain('\u001b', result);
        Assert.DoesNotContain('\u2028', result);
        Assert.DoesNotContain('\u202e', result);
    }

    private sealed class CountingStream(byte[] bytes) : MemoryStream(bytes)
    {
        public int BytesRead { get; private set; }
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            var result = base.ReadAsync(buffer, cancellationToken);
            if (result.IsCompletedSuccessfully) BytesRead += result.Result;
            return result;
        }
    }
}
