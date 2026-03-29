using System.Net;
using System.Text;
using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Export;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class IssueExportProviderTests : IDisposable
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly string rootDirectory;

    public IssueExportProviderTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        var storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));
        diagnostics = new WindowsDiagnostics(storagePaths);
    }

    [Fact]
    public async Task GitHubBuildRequest_IncludesAuthorizationAndIssueBody()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0];
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new GitHubExportConfiguration(
                Token: "fixture-github-token",
                Owner: "acme",
                Repository: "bugnarrator",
                Labels: ["bug", "triage"]));

        var body = await request.Content!.ReadAsStringAsync();
        using var document = JsonDocument.Parse(body);

        Assert.Equal("https://api.github.com/repos/acme/bugnarrator/issues", request.RequestUri!.AbsoluteUri);
        Assert.Equal("Bearer", request.Headers.Authorization?.Scheme);
        Assert.Equal("fixture-github-token", request.Headers.Authorization?.Parameter);
        Assert.Equal("Save button clips in the modal", document.RootElement.GetProperty("title").GetString());
        Assert.Equal(2, document.RootElement.GetProperty("labels").GetArrayLength());
        Assert.Contains("Transcript time", document.RootElement.GetProperty("body").GetString());
    }

    [Fact]
    public async Task GitHubExportAsync_ReportsPartialSuccessWhenLaterIssueFails()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: new IssueExtractionResult(
                GeneratedAt: DateTimeOffset.UtcNow,
                Summary: "Two issues",
                GuidanceNote: "Review before export.",
                Issues:
                [
                    ReviewSessionTestData.CreateIssueExtractionResult().Issues[0],
                    ReviewSessionTestData.CreateIssueExtractionResult().Issues[0] with
                    {
                        IssueId = Guid.NewGuid(),
                        Title = "Second issue",
                    },
                ]));

        var requestCount = 0;
        var provider = new GitHubExportProvider(
            diagnostics,
            new HttpClient(new TestHttpMessageHandler((request, _) =>
            {
                requestCount++;
                var statusCode = requestCount == 1 ? HttpStatusCode.Created : HttpStatusCode.UnprocessableEntity;
                var body = requestCount == 1
                    ? """{"number":101,"html_url":"https://github.com/acme/bugnarrator/issues/101"}"""
                    : """{"message":"Validation Failed"}""";

                return Task.FromResult(new HttpResponseMessage(statusCode)
                {
                    Content = new StringContent(body, Encoding.UTF8, "application/json"),
                });
            })));

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            provider.ExportAsync(
                session.IssueExtraction!.Issues,
                session,
                new GitHubExportConfiguration(
                    Token: "fixture-github-token",
                    Owner: "acme",
                    Repository: "bugnarrator",
                    Labels: Array.Empty<string>())));

        Assert.Contains("GitHub exported 1 issue(s)", exception.Message);
        Assert.Contains("Validation Failed", exception.Message);
    }

    [Fact]
    public async Task JiraBuildRequest_IncludesBasicAuthAndProjectFields()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0];
        var provider = new JiraExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new JiraExportConfiguration(
                BaseUrl: new Uri("https://acme.atlassian.net/"),
                Email: "you@example.com",
                ApiToken: "fixture-jira-token",
                ProjectKey: "BN",
                IssueType: "Task"));

        var body = await request.Content!.ReadAsStringAsync();
        using var document = JsonDocument.Parse(body);
        var fields = document.RootElement.GetProperty("fields");

        Assert.Equal("https://acme.atlassian.net/rest/api/3/issue", request.RequestUri!.AbsoluteUri);
        Assert.StartsWith("Basic ", request.Headers.Authorization!.ToString());
        Assert.Equal("BN", fields.GetProperty("project").GetProperty("key").GetString());
        Assert.Equal("Task", fields.GetProperty("issuetype").GetProperty("name").GetString());
        Assert.Equal("Save button clips in the modal", fields.GetProperty("summary").GetString());
    }

    [Fact]
    public async Task JiraExportAsync_MapsValidationFailure()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var provider = new JiraExportProvider(
            diagnostics,
            new HttpClient(new TestHttpMessageHandler((request, _) =>
                Task.FromResult(new HttpResponseMessage(HttpStatusCode.BadRequest)
                {
                    Content = new StringContent(
                        """{"errorMessages":["Issue type is invalid"],"errors":{}}""",
                        Encoding.UTF8,
                        "application/json"),
                }))));

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            provider.ExportAsync(
                session.IssueExtraction!.Issues,
                session,
                new JiraExportConfiguration(
                    BaseUrl: new Uri("https://acme.atlassian.net/"),
                    Email: "you@example.com",
                    ApiToken: "fixture-jira-token",
                    ProjectKey: "BN",
                    IssueType: "Task")));

        Assert.Contains("Issue type is invalid", exception.Message);
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }
}
