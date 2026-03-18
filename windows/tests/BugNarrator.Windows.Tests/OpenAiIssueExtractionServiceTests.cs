using System.Net;
using System.Text;
using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Extraction;
using BugNarrator.Windows.Services.Storage;
using Xunit;

namespace BugNarrator.Windows.Tests;

public sealed class OpenAiIssueExtractionServiceTests : IDisposable
{
    private readonly string rootDirectory;
    private readonly AppStoragePaths storagePaths;

    public OpenAiIssueExtractionServiceTests()
    {
        rootDirectory = Path.Combine(
            Path.GetTempPath(),
            "BugNarrator.Windows.Tests",
            Guid.NewGuid().ToString("N"));
        storagePaths = new AppStoragePaths(
            RootDirectory: rootDirectory,
            SessionsDirectory: Path.Combine(rootDirectory, "Sessions"),
            LogsDirectory: Path.Combine(rootDirectory, "Logs"));
    }

    [Fact]
    public async Task ExtractAsync_ReturnsStructuredDraftIssues()
    {
        var diagnostics = new WindowsDiagnostics(storagePaths);
        var screenshot = ReviewSessionTestData.CreateScreenshot(rootDirectory);
        var session = ReviewSessionTestData.CreateCompletedSession(
            rootDirectory,
            screenshots: [screenshot]);

        HttpRequestMessage? capturedRequest = null;
        var handler = new TestHttpMessageHandler((request, _) =>
        {
            capturedRequest = request;
            var body =
                """
                {
                  "choices": [
                    {
                      "message": {
                        "content": {
                          "type": "unsupported"
                        }
                      }
                    }
                  ]
                }
                """;

            // Return array-based content to exercise the defensive parser path.
            body =
                """
                {
                  "choices": [
                    {
                      "message": {
                        "content": [
                          {
                            "type": "text",
                            "text": "```json\n{\n  \"reviewSummary\": \"One draft issue was extracted.\",\n  \"guidance_note\": \"Review before export.\",\n  \"draftIssues\": [\n    {\n      \"issueTitle\": \"Save button clips in the modal\",\n      \"type\": \"Bug\",\n      \"description\": \"The save button appears clipped in the modal layout.\",\n      \"evidence\": \"The save button is clipped.\",\n      \"timecode\": \"00:08\",\n      \"section\": \"Save flow\",\n      \"screenshotFileNames\": [\"review-shot.png\"],\n      \"score\": 0.74,\n      \"needsReview\": true\n    }\n  ]\n}\n```"
                          }
                        ]
                      }
                    }
                  ]
                }
                """;

            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(body, Encoding.UTF8, "application/json"),
            });
        });

        var service = new OpenAiIssueExtractionService(
            diagnostics,
            new HttpClient(handler));

        var result = await service.ExtractAsync(session, "test-key", "gpt-4.1-mini");

        Assert.NotNull(capturedRequest);
        Assert.Equal("https://api.openai.com/v1/chat/completions", capturedRequest!.RequestUri!.AbsoluteUri);
        Assert.Equal("Bearer", capturedRequest.Headers.Authorization?.Scheme);
        Assert.Equal("test-key", capturedRequest.Headers.Authorization?.Parameter);
        Assert.Equal("One draft issue was extracted.", result.Summary);
        Assert.Equal("Review before export.", result.GuidanceNote);

        var issue = Assert.Single(result.Issues);
        Assert.Equal("Save button clips in the modal", issue.Title);
        Assert.Equal(ExtractedIssueCategory.Bug, issue.Category);
        Assert.Equal([screenshot.ScreenshotId], issue.RelatedScreenshotIds);
        Assert.Equal(8, issue.TimestampSeconds);
    }

    [Fact]
    public async Task ExtractAsync_WhenNetworkFails_ReturnsFriendlyConnectivityMessage()
    {
        var diagnostics = new WindowsDiagnostics(storagePaths);
        var session = ReviewSessionTestData.CreateCompletedSession(rootDirectory);
        var service = new OpenAiIssueExtractionService(
            diagnostics,
            new HttpClient(new TestHttpMessageHandler((request, cancellationToken) =>
                throw new HttpRequestException("No route to host"))));

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            service.ExtractAsync(session, "test-key", "gpt-4.1-mini"));

        Assert.Contains("could not reach OpenAI issue extraction", exception.Message, StringComparison.OrdinalIgnoreCase);
    }

    public void Dispose()
    {
        if (Directory.Exists(rootDirectory))
        {
            Directory.Delete(rootDirectory, recursive: true);
        }
    }
}
