using System.Linq;
using System.Net;
using System.IO;
using System.Text;
using BugNarrator.Windows.Services.LocalTranscription;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>WIN-038 (#1180): the Parakeet readiness probe, same rule as macOS isHealthyLocalProvider.</summary>
public sealed class LocalServerHealthProbeTests : IDisposable
{
    /// <summary>
    /// The probe reads the token from the install directory, and reading a
    /// token that is not there creates one. A test must not leave that in the
    /// user's own configuration directory, so it gets a scratch one.
    /// </summary>
    private readonly string installDirectory = Path.Combine(
        Path.GetTempPath(),
        "BugNarrator.Windows.Tests",
        Guid.NewGuid().ToString("N"));

    private LocalServerHealthProbe Probe(HttpClient? client = null) =>
        new(client, installDirectory);

    [Theory]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"ok\",\"model_loaded\":true,\"model\":\"parakeet-tdt-0.6b-v3\"}", true)]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"ok\"}", false)]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"ok\",\"model_loaded\":false}", false)]
    [InlineData(HttpStatusCode.OK, "{\"status\":\"loading\"}", false)]
    [InlineData(HttpStatusCode.OK, "{\"other\":\"ok\"}", false)]
    [InlineData(HttpStatusCode.OK, "not json", false)]
    [InlineData(HttpStatusCode.OK, "", false)]
    [InlineData(HttpStatusCode.OK, "[\"ok\"]", false)]
    [InlineData(HttpStatusCode.ServiceUnavailable, "{\"status\":\"ok\"}", false)]
    [InlineData(HttpStatusCode.NotFound, "{\"status\":\"ok\"}", false)]
    public void IsHealthy_RequiresA200WithJsonStatusOkAndAModelLoaded(HttpStatusCode status, string body, bool expected)
    {
        Assert.Equal(expected, LocalServerHealthProbe.IsHealthy(status, body));
    }

    [Fact]
    public async Task IsReachable_AsksTheHealthEndpointUncached()
    {
        HttpRequestMessage? sent = null;
        var probe = Probe(new HttpClient(new FakeHandler(request =>
        {
            sent = request;
            return Proved(request, "{\"status\":\"ok\",\"model_loaded\":true}");
        })));

        Assert.True(await probe.IsReachableAsync("http://localhost:8422"));
        Assert.Equal("http://localhost:8422/health", sent!.RequestUri!.AbsoluteUri);
        Assert.True(sent.Headers.CacheControl!.NoCache);
    }

    [Fact]
    public async Task IsReachable_ChallengesThePeerWithoutHandingItTheToken()
    {
        // The peer has to prove that it is the server before the app hands it
        // anything: a listener that answers on the port must not learn the
        // token from the first request the app sends (#1270).
        HttpRequestMessage? sent = null;
        var probe = Probe(new HttpClient(new FakeHandler(request =>
        {
            sent = request;
            return Proved(request, "{\"status\":\"ok\",\"model_loaded\":true}");
        })));

        Assert.True(await probe.IsReachableAsync("http://localhost:8422"));

        Assert.Null(sent!.Headers.Authorization);
        var nonce = sent.Headers.GetValues(LocalServerTokenStore.ChallengeHeader).Single();
        Assert.False(string.IsNullOrWhiteSpace(nonce));
    }

    [Fact]
    public async Task IsReachable_IsFalseWhenThePeerCannotProveItIsTheServer()
    {
        // A listener that answers the health check with the right body is
        // still not the server: it cannot produce the proof, so the app must
        // not upload the user's audio to it (#1270).
        var probe = Probe(new HttpClient(new FakeHandler(request =>
            Json("{\"status\":\"ok\",\"model_loaded\":true}"))));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
    }

    [Fact]
    public async Task IsReachable_IsFalseWhenThePeerProvesItWithTheWrongAnswer()
    {
        var probe = Probe(new HttpClient(new FakeHandler(request =>
        {
            var response = Json("{\"status\":\"ok\",\"model_loaded\":true}");
            response.Headers.TryAddWithoutValidation(LocalServerTokenStore.ProofHeader, "not-the-proof");
            return response;
        })));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
    }

    [Fact]
    public async Task IsReachable_IsFalseOnANonOkAnswer()
    {
        var probe = Probe(new HttpClient(new FakeHandler(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError))));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422/"));
    }

    [Fact]
    public async Task IsReachable_IsFalseWhenTheConnectionIsRefused()
    {
        var probe = Probe(new HttpClient(new FakeHandler(_ => throw new HttpRequestException("connection refused"))));

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
    }

    [Fact]
    public async Task IsReachable_IsFalseAfterTheTwoSecondTimeout()
    {
        var probe = Probe(new HttpClient(new SlowHandler()));
        var started = DateTimeOffset.UtcNow;

        Assert.False(await probe.IsReachableAsync("http://localhost:8422"));
        Assert.InRange(DateTimeOffset.UtcNow - started, LocalServerHealthProbe.Timeout - TimeSpan.FromMilliseconds(200), TimeSpan.FromSeconds(6));
    }

    [Fact]
    public async Task IsReachable_AgainstARefusedRealPort_IsFalse()
    {
        // A closed loopback port: the real transport path, not a fake handler.
        var listener = new TcpListenerHolder();
        var probe = Probe();

        Assert.False(await probe.IsReachableAsync($"http://127.0.0.1:{listener.ClosedPort}"));
    }

    [Fact]
    public async Task IsReachable_PropagatesTheCallersCancellation()
    {
        using var cancellation = new CancellationTokenSource();
        var probe = Probe(new HttpClient(new FakeHandler(_ => { cancellation.Cancel(); throw new OperationCanceledException(cancellation.Token); })));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => probe.IsReachableAsync("http://localhost:8422", cancellation.Token));
    }

    private static HttpResponseMessage Json(string body) =>
        new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };

    /// <summary>
    /// The answer the server gives to a challenge: the body and the proof
    /// that it knows the token.
    /// </summary>
    private HttpResponseMessage Proved(HttpRequestMessage request, string body)
    {
        var nonce = request.Headers.GetValues(LocalServerTokenStore.ChallengeHeader).Single();
        var token = LocalServerTokenStore.Token(installDirectory)!;
        var response = Json(body);
        response.Headers.TryAddWithoutValidation(
            LocalServerTokenStore.ProofHeader,
            LocalServerTokenStore.Proof(nonce, token));
        return response;
    }

    public void Dispose()
    {
        if (Directory.Exists(installDirectory))
        {
            Directory.Delete(installDirectory, recursive: true);
        }
    }

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
