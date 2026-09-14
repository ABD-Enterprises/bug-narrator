using System.Net;
using System.Text;
using BugNarrator.Windows.Services.LocalTranscription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>WIN-038 (#1180): the Parakeet readiness probe, same rule as macOS isHealthyLocalProvider.</summary>
public sealed class LocalServerHealthProbeTests
{
    [Theory]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"ok\",\"model\":\"parakeet-tdt-0.6b-v3\"}", true)]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"loading\"}", false)]
    [InlineData(HttpStatusCode.OK, "{\"other\":\"ok\"}", false)]
    [InlineData(HttpStatusCode.OK, "not json", false)]
    [InlineData(HttpStatusCode.OK, "", false)]
    [InlineData(HttpStatusCode.OK, "[\"ok\"]", false)]
    [InlineData(HttpStatusCode.ServiceUnavailable, "{\"status\":\"ok\"}", false)]
    [InlineData(HttpStatusCode.NotFound, "{\"status\":\"ok\"}", false)]
    public void IsHealthy_RequiresA200WithJsonStatusOk(HttpStatusCode status, string body, bool expected)
    {
        Assert.Equal(expected, LocalServerHealthProbe.IsHealthy(status, body));
    }

    [Fact]
    public async Task IsReachable_AsksTheHealthEndpointUncached()
    {
        HttpRequestMessage? sent = null;
        var probe = new LocalServerHealthProbe(new HttpClient(new FakeHandler(request =>
        {
            sent = request;
            return Json("{\"status\":\"ok\"}");
        })));

        Assert.True(await probe.IsReachableAsync("http://localhost:8422"));
        Assert.Equal("http://localhost:8422/health", sent!.RequestUri!.AbsoluteUri);
        Assert.True(sent.Headers.CacheControl!.NoCache);
    }

    [Fact]
    public async Task IsReachable_IsFalseOnANonOkAnswer()
    {
        var probe = new LocalServerHealthProbe(new HttpClient(new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError))));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422/"));
    }

    [Fact]
    public async Task IsReachable_IsFalseWhenTheConnectionIsRefused()
    {
        var probe = new LocalServerHealthProbe(new HttpClient(new FakeHandler(_ => throw new HttpRequestException("connection refused"))));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
    }

    [Fact]
    public async Task IsReachable_IsFalseAfterTheTwoSecondTimeout()
    {
        var probe = new LocalServerHealthProbe(new HttpClient(new SlowHandler()));
        var started = DateTimeOffset.UtcNow;

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
        Assert.InRange(DateTimeOffset.UtcNow - started, LocalServerHealthProbe.Timeout - TimeSpan.FromMilliseconds(200), TimeSpan.FromSeconds(6));
    }

    [Fact]
    public async Task IsReachable_AgainstARefusedRealPort_IsFalse()
    {
        // A closed loopback port: the real transport path, not a fake handler.
        var listener = new TcpListenerHolder();
        var probe = new LocalServerHealthProbe();

        Assert.False(await probe.IsReachableAsync($"http://127.0.0.1:{listener.ClosedPort}"));
    }

    [Fact]
    public async Task IsReachable_PropagatesTheCallersCancellation()
    {
        using var cancellation = new CancellationTokenSource();
        var probe = new LocalServerHealthProbe(new HttpClient(new FakeHandler(_ => { cancellation.Cancel(); throw new OperationCanceledException(cancellation.Token); })));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => probe.IsReachableAsync("http://localhost:8422", cancellation.Token));
    }

    private static HttpResponseMessage Json(string body) =>
        new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    private sealed class FakeHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(respond(request));
    }

    private sealed class SlowHandler : HttpMessageHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), cancellationToken);
            return Json("{\"status\":\"ok\"}");
        }
    }

    /// <summary>Finds a port that is definitely closed by binding one, reading it, and releasing it.</summary>
    private sealed class TcpListenerHolder
    {
        public int ClosedPort { get; }

        public TcpListenerHolder()
        {
            var listener = new System.Net.Sockets.TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            ClosedPort = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
        }
    }
}
