using System.Net;
using System.Net.Http;
using System.Text;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Http;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

/// <summary>
/// #1269: a failed response body reaches the log file, so the read has to be
/// bounded and the message has to be safe to write down.
/// </summary>
public sealed class ResponseBodyReaderTests
{
    private static HttpResponseMessage Response(HttpStatusCode status, byte[] body)
    {
        var response = new HttpResponseMessage(status);
        response.Content = new ByteArrayContent(body);
        return response;
    }

    [Fact]
    public async Task ReadsAtMostTheBoundEvenWhenTheServerAnswersWithMore()
    {
        using var response = Response(HttpStatusCode.BadRequest, new byte[1024 * 1024]);

        var body = await ResponseBodyReader.ReadErrorBodyAsync(response);

        Assert.Equal(ResponseBodyReader.MaxErrorBodyBytes, body.Length);
    }

    [Fact]
    public async Task ReadsAShortBodyWhole()
    {
        using var response = Response(HttpStatusCode.BadRequest, Encoding.UTF8.GetBytes("{\"message\":\"nope\"}"));

        var body = await ResponseBodyReader.ReadErrorBodyAsync(response);

        Assert.Equal("{\"message\":\"nope\"}", body);
    }

    [Fact]
    public async Task ReadsNothingFromAnEmptyBody()
    {
        using var response = Response(HttpStatusCode.BadRequest, Array.Empty<byte>());

        var body = await ResponseBodyReader.ReadErrorBodyAsync(response);

        Assert.Equal(string.Empty, body);
    }

    [Fact]
    public void CutsAMessageThatWouldFillTheLog()
    {
        var message = new string('x', ResponseBodyReader.MaxLoggedMessageCharacters * 2);

        var loggable = ResponseBodyReader.ToLoggableMessage(message);

        Assert.Equal(
            ResponseBodyReader.MaxLoggedMessageCharacters + " [truncated]".Length,
            loggable.Length);
        Assert.EndsWith(" [truncated]", loggable);
    }

    [Fact]
    public void KeepsAShortMessageAsItIs()
    {
        Assert.Equal("GitHub rejected the issue.", ResponseBodyReader.ToLoggableMessage("GitHub rejected the issue."));
    }

    /// <summary>
    /// A body with newlines in it would otherwise forge a log line that looks
    /// like it came from somewhere else.
    /// </summary>
    [Fact]
    public void ReplacesControlCharactersSoTheBodyCannotForgeALogLine()
    {
        var message = "first line\r\n2026-01-01 [INFO] forged line\nthird";

        var loggable = ResponseBodyReader.ToLoggableMessage(message);

        Assert.DoesNotContain('\r', loggable);
        Assert.DoesNotContain('\n', loggable);
        Assert.Contains("first line", loggable);
        Assert.Contains("forged line", loggable);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void TreatsAnEmptyMessageAsEmpty(string? message)
    {
        Assert.Equal(string.Empty, ResponseBodyReader.ToLoggableMessage(message));
    }

    /// <summary>
    /// The end-to-end shape of the finding: a server that answers a failed
    /// request with a huge body must not put that body into the log file.
    /// </summary>
    [Fact]
    public async Task AHugeFailureBodyDoesNotReachTheLogFile()
    {
        var rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        var storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));
        var diagnostics = new WindowsDiagnostics(storagePaths);

        var huge = new string('x', 512 * 1024);
        var payload = $"{{\"message\":\"{huge}\"}}";
        var handler = new TestHttpMessageHandler((_, _) => Task.FromResult(
            new HttpResponseMessage(HttpStatusCode.UnprocessableEntity)
            {
                Content = new StringContent(payload, Encoding.UTF8, "application/json"),
            }));
        var provider = new GitHubExportProvider(diagnostics, new HttpClient(handler));

        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0];

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() => provider.ExportAsync(
            [issue],
            session,
            new GitHubExportConfiguration(
                Token: "fixture-github-token",
                Owner: "acme",
                Repository: "bugnarrator",
                Labels: ["bug"])));

        Assert.DoesNotContain(huge, exception.Message);
        Assert.True(
            exception.Message.Length < 4096,
            $"the message was {exception.Message.Length} characters, so it would still fill the log");

        var log = File.Exists(diagnostics.LogFilePath)
            ? await File.ReadAllTextAsync(diagnostics.LogFilePath)
            : string.Empty;
        Assert.DoesNotContain(huge, log);
    }
}
