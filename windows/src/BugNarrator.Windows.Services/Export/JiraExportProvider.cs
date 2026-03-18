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

public sealed class JiraExportProvider
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly WindowsDiagnostics diagnostics;
    private readonly HttpClient httpClient;

    public JiraExportProvider(
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
        JiraExportConfiguration configuration,
        CancellationToken cancellationToken = default)
    {
        if (!configuration.IsComplete)
        {
            throw new InvalidOperationException(
                "Jira export requires a base URL, email, API token, project key, and issue type in Settings.");
        }

        diagnostics.Info(
            "export",
            $"Jira export requested for {issues.Count} issue(s) to project {configuration.ProjectKey}");

        var results = new List<IssueExportResult>();
        foreach (var issue in issues)
        {
            using var request = BuildRequest(issue, session, configuration);
            using var response = await RemoteServiceRequestGuard.SendAsync(
                httpClient,
                request,
                "Jira",
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

            var payload = JsonSerializer.Deserialize<JiraIssueResponse>(responseBody, JsonOptions)
                          ?? throw new InvalidOperationException("Jira returned an invalid issue response.");

            results.Add(new IssueExportResult(
                SourceIssueId: issue.IssueId,
                Destination: IssueExportDestination.Jira,
                RemoteIdentifier: payload.Key,
                RemoteUrl: configuration.BaseUrl.AppendPathSegment($"browse/{payload.Key}"),
                ExportedAt: DateTimeOffset.UtcNow));
        }

        diagnostics.Info("export", $"Jira export completed with {results.Count} issue(s)");
        return results;
    }

    public HttpRequestMessage BuildRequest(
        ExtractedIssue issue,
        CompletedSession session,
        JiraExportConfiguration configuration)
    {
        var request = new HttpRequestMessage(
            HttpMethod.Post,
            configuration.BaseUrl.AppendPathSegment("rest/api/3/issue"));
        request.Headers.Authorization = new AuthenticationHeaderValue(
            "Basic",
            Convert.ToBase64String(Encoding.UTF8.GetBytes($"{configuration.Email}:{configuration.ApiToken}")));
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
        request.Headers.UserAgent.Add(new ProductInfoHeaderValue("BugNarrator", "1.0"));

        var payload = new JiraIssueRequest(
            new JiraIssueFields(
                new JiraProjectField(configuration.ProjectKey),
                issue.Title,
                new JiraIssueTypeField(configuration.IssueType),
                BuildDescription(issue, session)));

        request.Content = new StringContent(
            JsonSerializer.Serialize(payload, JsonOptions),
            Encoding.UTF8,
            "application/json");
        return request;
    }

    private static JiraDocument BuildDescription(ExtractedIssue issue, CompletedSession session)
    {
        var blocks = new List<JiraBlock>
        {
            JiraBlock.Paragraph($"Summary: {issue.Summary}"),
            JiraBlock.Paragraph($"Evidence: {issue.EvidenceExcerpt}"),
        };

        var metadataLines = new List<string>();
        if (issue.TimestampLabel is not null)
        {
            metadataLines.Add($"Transcript time: {issue.TimestampLabel}");
        }

        if (!string.IsNullOrWhiteSpace(issue.SectionTitle))
        {
            metadataLines.Add($"Transcript section: {issue.SectionTitle}");
        }

        if (issue.ConfidenceLabel is not null)
        {
            metadataLines.Add($"Confidence: {issue.ConfidenceLabel}");
        }

        if (issue.RequiresReview)
        {
            metadataLines.Add("Review needed: Yes");
        }

        if (!string.IsNullOrWhiteSpace(issue.Note))
        {
            metadataLines.Add($"Note: {issue.Note}");
        }

        if (metadataLines.Count > 0)
        {
            blocks.Add(JiraBlock.BulletList(metadataLines));
        }

        var screenshots = session.Screenshots
            .Where(screenshot => issue.RelatedScreenshotIds.Contains(screenshot.ScreenshotId))
            .OrderBy(screenshot => screenshot.ElapsedSeconds)
            .Select(screenshot =>
                $"{Path.GetFileName(screenshot.RelativePath)} ({SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)}) - attach manually from the exported session bundle if needed.")
            .ToArray();

        if (screenshots.Length > 0)
        {
            blocks.Add(JiraBlock.Paragraph("Related screenshots"));
            blocks.Add(JiraBlock.BulletList(screenshots));
        }

        blocks.Add(JiraBlock.Paragraph(
            $"Exported from BugNarrator session \"{session.Title}\" recorded {session.CreatedAt:yyyy-MM-dd HH:mm:ss zzz}. Review against the raw transcript before triage."));

        return new JiraDocument(blocks);
    }

    private static string BuildFailureMessage(
        HttpStatusCode statusCode,
        string responseBody,
        JiraExportConfiguration configuration,
        int successfulCount)
    {
        var message = TryReadMessage(responseBody) ?? statusCode.ToString();
        var normalizedMessage = message.ToLowerInvariant();

        var failureMessage = statusCode switch
        {
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden when normalizedMessage.Contains("rate limit") =>
                "Jira rate limited the request. Wait a moment and try again.",
            HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden =>
                $"Jira rejected the credentials for project {configuration.ProjectKey}.",
            HttpStatusCode.NotFound =>
                $"Jira could not find the configured site or project {configuration.ProjectKey}.",
            HttpStatusCode.BadRequest =>
                $"Jira rejected the issue payload: {message}",
            _ => $"Jira returned {(int)statusCode}: {message}",
        };

        return successfulCount > 0
            ? $"Jira exported {successfulCount} issue(s) before failing. {failureMessage}"
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
            var messages = new List<string>();

            if (document.RootElement.TryGetProperty("errorMessages", out var errorMessages)
                && errorMessages.ValueKind == JsonValueKind.Array)
            {
                messages.AddRange(
                    errorMessages.EnumerateArray()
                        .Where(item => item.ValueKind == JsonValueKind.String)
                        .Select(item => item.GetString()!)
                        .Where(item => !string.IsNullOrWhiteSpace(item)));
            }

            if (document.RootElement.TryGetProperty("errors", out var errors)
                && errors.ValueKind == JsonValueKind.Object)
            {
                messages.AddRange(
                    errors.EnumerateObject()
                        .Select(property => property.Value.GetString())
                        .Where(value => !string.IsNullOrWhiteSpace(value))!);
            }

            return messages.Count == 0 ? null : string.Join(" ", messages);
        }
        catch
        {
            return null;
        }
    }

    private sealed record JiraIssueRequest(
        [property: JsonPropertyName("fields")] JiraIssueFields Fields);

    private sealed record JiraIssueFields(
        [property: JsonPropertyName("project")] JiraProjectField Project,
        [property: JsonPropertyName("summary")] string Summary,
        [property: JsonPropertyName("issuetype")] JiraIssueTypeField IssueType,
        [property: JsonPropertyName("description")] JiraDocument Description);

    private sealed record JiraProjectField(
        [property: JsonPropertyName("key")] string Key);

    private sealed record JiraIssueTypeField(
        [property: JsonPropertyName("name")] string Name);

    private sealed record JiraIssueResponse(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("key")] string Key);

    private sealed record JiraDocument(
        [property: JsonPropertyName("content")] IReadOnlyList<JiraBlock> Content)
    {
        [JsonPropertyName("type")]
        public string Type => "doc";

        [JsonPropertyName("version")]
        public int Version => 1;
    }

    private sealed record JiraBlock(
        [property: JsonPropertyName("type")] string Type,
        [property: JsonPropertyName("content")] IReadOnlyList<JiraInline> Content)
    {
        public static JiraBlock Paragraph(string text)
        {
            return new JiraBlock("paragraph", [JiraInline.TextNode(text)]);
        }

        public static JiraBlock BulletList(IEnumerable<string> items)
        {
            return new JiraBlock(
                "bulletList",
                items.Select(item => JiraInline.ListItem(Paragraph(item))).ToArray());
        }
    }

    private sealed record JiraInline(
        [property: JsonPropertyName("type")] string Type,
        [property: JsonPropertyName("text")] string? Text,
        [property: JsonPropertyName("content")] IReadOnlyList<JiraBlock>? Content)
    {
        public static JiraInline TextNode(string value)
        {
            return new JiraInline("text", value, null);
        }

        public static JiraInline ListItem(JiraBlock block)
        {
            return new JiraInline("listItem", null, [block]);
        }
    }
}

internal static class UriExtensions
{
    public static Uri AppendPathSegment(this Uri baseUri, string relativePath)
    {
        return new Uri(baseUri, relativePath);
    }
}
