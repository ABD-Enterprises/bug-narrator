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
    public async Task GitHubBuildRequest_IncludesSeverityComponentAndDeduplicationHint()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with
        {
            Severity = ExtractedIssueSeverity.High,
            Component = "Save flow",
        };
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new GitHubExportConfiguration("t", "acme", "bugnarrator", []));

        var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync())
            .RootElement.GetProperty("body").GetString()!;

        Assert.Contains("- Severity: High", body);
        Assert.Contains("- Component: Save flow", body);
        Assert.Contains("- Deduplication hint: `issue-", body);

        // macOS orders these after the transcript time and before the transcript section.
        Assert.True(body.IndexOf("- Transcript time", StringComparison.Ordinal)
            < body.IndexOf("- Severity:", StringComparison.Ordinal));
        Assert.True(body.IndexOf("- Severity:", StringComparison.Ordinal)
            < body.IndexOf("- Component:", StringComparison.Ordinal));
        Assert.True(body.IndexOf("- Component:", StringComparison.Ordinal)
            < body.IndexOf("- Deduplication hint:", StringComparison.Ordinal));
        Assert.True(body.IndexOf("- Deduplication hint:", StringComparison.Ordinal)
            < body.IndexOf("- Transcript section:", StringComparison.Ordinal));
    }

    [Fact]
    public async Task GitHubBuildRequest_OmitsComponentLineWhenComponentIsMissing()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with { Component = null };
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new GitHubExportConfiguration("t", "acme", "bugnarrator", []));

        var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync())
            .RootElement.GetProperty("body").GetString()!;

        Assert.DoesNotContain("- Component:", body);
        // Severity and the dedup hint are unconditional, so they must still be present.
        Assert.Contains("- Severity:", body);
        Assert.Contains("- Deduplication hint:", body);
    }

    [Fact]
    public async Task JiraBuildRequest_IncludesSeverityComponentAndDeduplicationHint()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with
        {
            Severity = ExtractedIssueSeverity.Critical,
            Component = "Export",
        };
        var provider = new JiraExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new JiraExportConfiguration(
                new Uri("https://acme.atlassian.net/"), "you@example.com", "t", "BN", "Task"));

        var body = await request.Content!.ReadAsStringAsync();

        Assert.Contains("Severity: Critical", body);
        Assert.Contains("Component: Export", body);
        // Jira metadata lines are plain text, not backticked like the GitHub body.
        Assert.Contains("Deduplication hint: issue-", body);
    }

    [Fact]
    public async Task GitHubBuildRequest_RendersReproductionStepsLikeMac()
    {
        var screenshot = ReviewSessionTestData.CreateScreenshot(rootDirectory);
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            screenshots: [screenshot],
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with
        {
            ReproductionSteps =
            [
                new IssueReproductionStep(
                    Guid.NewGuid(), "Open checkout", "Button visible", "Right edge cut off", 30, screenshot.ScreenshotId),
                new IssueReproductionStep(Guid.NewGuid(), "Resize window", null, null, null, null),
            ],
        };
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue, session, new GitHubExportConfiguration("t", "acme", "bugnarrator", []));
        var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync())
            .RootElement.GetProperty("body").GetString()!;

        Assert.Contains("## Reproduction Steps", body);
        Assert.Contains("1. Open checkout", body);
        Assert.Contains("   - Expected: Button visible", body);
        Assert.Contains("   - Actual: Right edge cut off", body);
        // Assert the whole Reference line so the screenshot name is proven to come from the step,
        // not from the separate "Related Screenshots" section.
        Assert.Contains(
            $"   - Reference: Transcript `00:30`  •  Screenshot `{Path.GetFileName(screenshot.RelativePath)}` (`00:08`)",
            body);
        // A step with no optional fields renders as a bare numbered line.
        Assert.Contains("2. Resize window", body);
    }

    [Fact]
    public async Task GitHubBuildRequest_CapsReproductionStepsAtTheTrackerBudget()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with
        {
            ReproductionSteps = Enumerable.Range(1, 12)
                .Select(i => new IssueReproductionStep(Guid.NewGuid(), $"Step {i}", null, null, null, null))
                .ToArray(),
        };
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue, session, new GitHubExportConfiguration("t", "acme", "bugnarrator", []));
        var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync())
            .RootElement.GetProperty("body").GetString()!;

        Assert.Contains("10. Step 10", body);
        Assert.DoesNotContain("11. Step 11", body);
        // macOS drops steps past the cap silently — no omission notice for reproduction steps.
        Assert.DoesNotContain("Additional items were omitted", body);
    }

    [Fact]
    public async Task GitHubBuildRequest_OmitsReproductionSectionWhenThereAreNoSteps()
    {
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var provider = new GitHubExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            session.IssueExtraction!.Issues[0],
            session,
            new GitHubExportConfiguration("t", "acme", "bugnarrator", []));
        var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync())
            .RootElement.GetProperty("body").GetString()!;

        Assert.DoesNotContain("## Reproduction Steps", body);
    }

    [Fact]
    public async Task JiraBuildRequest_RendersReproductionStepsInTheMacTextShape()
    {
        var screenshot = ReviewSessionTestData.CreateScreenshot(rootDirectory);
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            screenshots: [screenshot],
            issueExtraction: ReviewSessionTestData.CreateIssueExtractionResult());
        var issue = session.IssueExtraction!.Issues[0] with
        {
            ReproductionSteps =
            [
                new IssueReproductionStep(
                    Guid.NewGuid(), "Open checkout", "Button visible", "Cut off", 30, screenshot.ScreenshotId),
            ],
        };
        var provider = new JiraExportProvider(diagnostics);

        using var request = provider.BuildRequest(
            issue,
            session,
            new JiraExportConfiguration(
                new Uri("https://acme.atlassian.net/"), "you@example.com", "t", "BN", "Task"));
        var body = await request.Content!.ReadAsStringAsync();

        Assert.Contains("Reproduction steps", body);

        // Assert the WHOLE entry, so the macOS separators (" | ", "Reference: ", " • ") are pinned.
        // Loose per-fragment assertions pass no matter how the parts are joined.
        var expected = "1. Open checkout | Expected: Button visible | Actual: Cut off | "
            + $"Reference: Transcript 00:30 • Screenshot {Path.GetFileName(screenshot.RelativePath)} (00:08)";
        Assert.Contains(JsonEncodedText.Encode(expected).ToString(), body);
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
