using System.Net.Http;
using System.Net;

namespace BugNarrator.Windows.Tests;

internal sealed class TestHttpMessageHandler : HttpMessageHandler
{
    private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler;

    public TestHttpMessageHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> handler)
    {
        this.handler = handler;
    }

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        return handler(request, cancellationToken);
    }
}

// Fails immediately if HttpClient eagerly buffers before the streaming reader
// can inspect Content-Length. No large payload is allocated by this fixture.
internal sealed class PrefetchDetectingContent : HttpContent
{
    public int SerializationCalls { get; private set; }
    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context)
    {
        SerializationCalls++;
        throw new InvalidOperationException("Unexpected eager response buffering");
    }
    protected override bool TryComputeLength(out long length)
    {
        length = 0;
        return false;
    }
}
