using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Http;

namespace BugNarrator.Windows.Services.Export;

public sealed class GitHubExportProvider
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly WindowsDiagnostics diagnostics;
    private readonly HttpClient httpClient;

    public GitHubExportProvider(
        WindowsDiagnostics diagnostics,
        HttpClient? httpClient = null)
    {
        this.diagnostics = diagnostics;
        this.httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(2),
        };
    }

    public async Task<IReadOnlyList<IssueExportResult>> ExportAsync(
        IReadOnlyList<ExtractedIssue> issues,
        CompletedSession session,
        GitHubExportConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        if (!configuration.IsComplete)
        {
            throw new InvalidOperationException(
                "GitHub export requires a token, repository owner, and repository name in Settings.");
        }

        diagnostics.Info(
            "export",
            $"GitHub export requested for {issues.Count} issue(s) to {configuration.Owner}/{configuration.Repository}");

        var results = new List<IssueExportResult>();
        foreach (var issue in issues)
        {
            using var request = BuildRequest(issue, session, configuration);
            using var response = await RemoteServiceRequestGuard.SendAsync(
                httpClient,
                request,
                "GitHub",
                cancellationToken);
            var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

            if (!response.IsSuccessStatusCode)
            {
                var message = BuildFailureMessage(
                    response.StatusCode,
                    responseBody,
                    configuration,
                    results.Count);
                diagnostics.Warning("export", message);
                throw new InvalidOperationException(message);
            }

            var payload = JsonSerializer.Deserialize<GitHubIssueResponse>(responseBody, JsonOptions)
                          ?? throw new InvalidOperationException("GitHub returned an invalid issue response.");

            results.Add(new IssueExportResult(
                SourceIssueId: issue.IssueId,
                Destination: IssueExportDestination.GitHub,
                RemoteIdentifier: $"#{payload.Number}",
                RemoteUrl: payload.HtmlUrl,
                ExportedAt: DateTimeOffset.UtcNow));
        }

        diagnostics.Info("export", $"GitHub export completed with {results.Count} issue(s)");
        return results;
    }

    public HttpRequestMessage BuildRequest(
        ExtractedIssue issue,
        CompletedSession session,
        GitHubExportConfiguration configuration)
    {
        var endpoint = new Uri(
            $"https://api.github.com/repos/{Uri.EscapeDataString(configuration.Owner)}/{Uri.EscapeDataString(configuration.Repository)}/issues");

        var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", configuration.Token);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.UserAgent.Add(new ProductInfoHeaderValue("BugNarrator", "1.0"));

        var payload = new GitHubIssueRequest(
            Title: issue.Title,
            Body: BuildIssueBody(issue, session),
            Labels: configuration.Labels.Count == 0 ? null : configuration.Labels);

        request.Content = new StringContent(
            JsonSerializer.Serialize(payload, JsonOptions),
            Encoding.UTF8,
            "application/json");
        return request;
    }

    private static string BuildIssueBody(ExtractedIssue issue, CompletedSession session)
    {
        var lines = new List<string>
        {
            "## Summary",
            issue.Summary,
            string.Empty,
            "## Evidence",
            issue.EvidenceExcerpt,
            string.Empty,
        };

        if (issue.TimestampLabel is not null)
        {
            lines.Add($"- Transcript time: `{issue.TimestampLabel}`");
        }

        if (!string.IsNullOrWhiteSpace(issue.SectionTitle))
        {
            lines.Add($"- Transcript section: {issue.SectionTitle}");
        }

        if (issue.ConfidenceLabel is not null)
        {
            lines.Add($"- Confidence: {issue.ConfidenceLabel}");
        }

        if (issue.RequiresReview)
        {
            lines.Add("- Review needed: Yes");
        }

        if (!string.IsNullOrWhiteSpace(issue.Note))
        {
            lines.Add($"- Note: {issue.Note}");
        }

        var screenshots = session.Screenshots
            .Where(screenshot => issue.RelatedScreenshotIds.Contains(screenshot.ScreenshotId))
            .OrderBy(screenshot => screenshot.ElapsedSeconds)
            .ToArray();

        if (screenshots.Length > 0)
        {
            lines.Add(string.Empty);
            lines.Add("## Related Screenshots");

            foreach (var screenshot in screenshots)
            {
                lines.Add(
                    $"- {Path.GetFileName(screenshot.RelativePath)} (`{SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)}`) - attach manually from the exported session bundle if needed.");
            }
        }

        lines.Add(string.Empty);
        lines.Add("## Source");
        lines.Add($"Exported from BugNarrator session \"{session.Title}\" recorded {session.CreatedAt:yyyy-MM-dd HH:mm:ss zzz}.");
        lines.Add("Review against the raw transcript before triage.");

        return string.Join(Environment.NewLine, lines);
    }

    private static string BuildFailureMessage(
        HttpStatusCode statusCode,
        string responseBody,
        GitHubExportConfiguration configuration,
        int successfulCount)
    {
        var message = TryReadMessage(responseBody) ?? statusCode.ToString();
        var normalizedMessage = message.ToLowerInvariant();

        var failureMessage = statusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden when normalizedMessage.Contains("rate limit") =>
                "GitHub rate limited the request. Wait a moment and try again.",
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden =>
                $"GitHub rejected the token or repository access for {configuration.Owner}/{configuration.Repository}.",
            HttpStatusCode.NotFound =>
                $"GitHub could not find {configuration.Owner}/{configuration.Repository}. Check the owner, repository name, and token permissions.",
            HttpStatusCode.UnprocessableEntity =>
                $"GitHub rejected the issue payload: {message}",
            _ => $"GitHub returned {(int)statusCode}: {message}",
        };

        return successfulCount > 0
            ? $"GitHub exported {successfulCount} issue(s) before failing. {failureMessage}"
            : failureMessage;
    }

    private static string? TryReadMessage(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(responseBody);
            return document.RootElement.TryGetProperty("message", out var messageElement)
                ? messageElement.GetString()?.Trim()
                : null;
        }
        catch
        {
            return null;
        }
    }

    private sealed record GitHubIssueRequest(
        [property: JsonPropertyName("title")] string Title,
        [property: JsonPropertyName("body")] string Body,
        [property: JsonPropertyName("labels")] IReadOnlyList<string>? Labels);

    private sealed record GitHubIssueResponse(
        [property: JsonPropertyName("number")] int Number,
        [property: JsonPropertyName("html_url")] Uri? HtmlUrl);
}
