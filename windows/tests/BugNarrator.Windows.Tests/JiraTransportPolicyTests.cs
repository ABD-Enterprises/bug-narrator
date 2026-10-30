using System.Net;
using System.Net.Sockets;
using System.Text;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Http;
using BugNarrator.Windows.Services.Settings;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class JiraTransportPolicyTests : IDisposable
{
    /// <summary>
    /// The refusal for a plaintext remote Jira URL has to say what the user
    /// loses if they accept it: the account email and the API token cross the
    /// network in the clear. The two refusals differ in why the host was refused
    /// - one the app knows to be remote, one it cannot check at all.
    /// </summary>
    [Fact]
    public void JiraBaseUrlSecurityWarning_NamesTheCredentialsItWouldSendInTheClear()
    {
        var remoteSettings = WindowsAppSettings.Default with { JiraBaseUrl = "http://8.8.8.8:8080/jira" };
        var remote = remoteSettings.JiraBaseUrlSecurityWarning;
        Assert.NotNull(remote);
        Assert.Contains("remote host", remote, StringComparison.Ordinal);
        Assert.Contains("email and API token would be sent unencrypted", remote, StringComparison.Ordinal);

        var uncheckableSettings = WindowsAppSettings.Default with { JiraBaseUrl = "http://jira.example.com:8080/jira" };
        var uncheckable = uncheckableSettings.JiraBaseUrlSecurityWarning;
        Assert.NotNull(uncheckable);
        Assert.Contains("cannot check as a local address", uncheckable, StringComparison.Ordinal);
        Assert.DoesNotContain("remote host", uncheckable, StringComparison.Ordinal);
        Assert.Contains("email and API token would be sent unencrypted", uncheckable, StringComparison.Ordinal);
    }

    /// <summary>
    /// The export gate refuses the same hosts as the settings warning and says
    /// why: a host the app parsed and found to be public is remote, a host it
    /// cannot parse is one it cannot check. Both refusals name what would cross
    /// the network in the clear.
    /// </summary>
    [Fact]
    public void CompatibilityIssue_NamesTheCredentialsItWouldSendInTheClear()
    {
        var remote = JiraEndpointTransportPolicy.CompatibilityIssue(new Uri("http://8.8.8.8:8080/jira"));
        Assert.NotNull(remote);
        Assert.Contains("remote host", remote, StringComparison.Ordinal);
        Assert.Contains("would cross the network unencrypted", remote, StringComparison.Ordinal);

        var uncheckable = JiraEndpointTransportPolicy.CompatibilityIssue(new Uri("http://jira.example.com:8080/jira"));
        Assert.NotNull(uncheckable);
        Assert.Contains("cannot check as a local address", uncheckable, StringComparison.Ordinal);
        Assert.DoesNotContain("remote host", uncheckable, StringComparison.Ordinal);
        Assert.Contains("would cross the network unencrypted", uncheckable, StringComparison.Ordinal);
    }

    private readonly string root = Path.Combine(Path.GetTempPath(), "BugNarrator.Windows.Tests", Guid.NewGuid().ToString("N"));
    private WindowsDiagnostics Diagnostics => new(new AppStoragePaths(root, Path.Combine(root, "Sessions"), Path.Combine(root, "Logs")));

    [Theory]
    [InlineData("https://jira.example.com/jira")]
    [InlineData("http://localhost:8080/jira")]
    [InlineData("http://127.0.0.1/jira")]
    [InlineData("http://[::1]/jira")]
    [InlineData("http://192.168.1.10/jira")]
    [InlineData("http://10.1.2.3/jira")]
    [InlineData("http://172.16.1.10/jira")]
    public void TrustedTransport_RemainsUsableForSettingsAndDirectRequests(string endpoint)
    {
        var settings = WindowsAppSettings.Default with { JiraBaseUrl = endpoint };
        Assert.Null(settings.JiraBaseUrlCompatibilityIssue);
        var session = Session();
        using var request = new JiraExportProvider(Diagnostics).BuildRequest(
            session.IssueExtraction!.Issues[0], session, Configuration(endpoint));
        Assert.Equal("Basic", request.Headers.Authorization!.Scheme);
    }

    [Theory]
    [InlineData("http://jira.example.com/jira")]
    [InlineData("HTTP://jira.example.com/jira")]
    [InlineData("http://localhost.evil.example/jira")]
    [InlineData("http://192.169.1.10/jira")]
    [InlineData("http://jira.local/jira")]
    [InlineData("ftp://jira.example.com/jira")]
    public async Task UnsafeTransport_IsRefusedEvenWhenBypassingSettings(string endpoint)
    {
        var settings = WindowsAppSettings.Default with { JiraBaseUrl = endpoint };
        Assert.NotNull(settings.JiraBaseUrlCompatibilityIssue);
        var calls = 0;
        using var client = new HttpClient(new TestHttpMessageHandler((_, _) =>
        {
            calls++;
            throw new InvalidOperationException("Fixture must not reach transport");
        }));
        var provider = new JiraExportProvider(Diagnostics, client);
        var session = Session();
        var configuration = Configuration(endpoint);

        Assert.Throws<InvalidOperationException>(() => provider.BuildRequest(session.IssueExtraction!.Issues[0], session, configuration));
        await Assert.ThrowsAsync<InvalidOperationException>(() => provider.ExportAsync(session.IssueExtraction!.Issues, session, configuration));
        Assert.Equal(0, calls);
    }

    [Fact]
    public void RelativeEndpoint_IsRejectedBeforeUriOrAuthConstruction()
    {
        Assert.NotNull(JiraEndpointTransportPolicy.CompatibilityIssue(new Uri("jira", UriKind.Relative)));
        Assert.NotNull(JiraEndpointTransportPolicy.CompatibilityIssue(null));
    }

    [Fact]
    public async Task DefaultClient_DoesNotForwardTheRequestBodyAcrossRedirects()
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var baseUrl = $"http://127.0.0.1:{((IPEndPoint)listener.LocalEndpoint).Port}";
        var forwarded = 0;
        var server = Task.Run(async () =>
        {
            for (var index = 0; index < 2; index++)
            {
                using var connection = await listener.AcceptTcpClientAsync(deadline.Token);
                if (index > 0)
                {
                    Interlocked.Increment(ref forwarded);
                }

                using var stream = connection.GetStream();
                var headers = new List<byte>();
                var singleByte = new byte[1];
                while (headers.Count < 64 * 1024)
                {
                    await stream.ReadExactlyAsync(singleByte, deadline.Token);
                    headers.Add(singleByte[0]);
                    if (headers.Count >= 4 && headers[^4] == '\r' && headers[^3] == '\n'
                        && headers[^2] == '\r' && headers[^1] == '\n')
                    {
                        break;
                    }
                }

                var headerText = Encoding.ASCII.GetString(headers.ToArray());
                var contentLength = headerText.Split("\r\n")
                    .First(line => line.StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase));
                var body = new byte[int.Parse(contentLength.Split(':')[1].Trim())];
                await stream.ReadExactlyAsync(body, deadline.Token);
                var response = index == 0
                    ? $"HTTP/1.1 307 Temporary Redirect\r\nLocation: {baseUrl}/forwarded\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    : "HTTP/1.1 201 Created\r\nContent-Length: 15\r\nConnection: close\r\n\r\n{\"key\":\"BN-42\"}";
                await stream.WriteAsync(Encoding.ASCII.GetBytes(response), deadline.Token);
            }
        });

        try
        {
            var session = Session();
            var provider = new JiraExportProvider(Diagnostics);
            var failure = await Assert.ThrowsAsync<InvalidOperationException>(() =>
                provider.ExportAsync(session.IssueExtraction!.Issues, session, Configuration(baseUrl), deadline.Token));
            Assert.Contains("redirect", failure.Message, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("Settings", failure.Message);
        }
        finally
        {
            deadline.Cancel();
            try { await server; }
            catch (OperationCanceledException) when (deadline.IsCancellationRequested) { }
            listener.Stop();
        }

        Assert.Equal(0, forwarded);
    }

    private CompletedSession Session() => ReviewSessionTestData.CreateCompletedSession(root,
        issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());

    private static JiraExportConfiguration Configuration(string endpoint) =>
        new(new Uri(endpoint), "fixture@example.com", "fixture-token", "BN", "Task");

    public void Dispose()
    {
        if (Directory.Exists(root))
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
