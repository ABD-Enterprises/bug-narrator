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
