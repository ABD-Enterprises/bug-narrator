using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using BugNarrator.Core.Extraction;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Http;

namespace BugNarrator.Windows.Services.Extraction;

public sealed class OpenAiIssueExtractionService : IIssueExtractionService
{
    private static readonly Uri ChatCompletionsEndpoint = new("https://api.openai.com/v1/chat/completions");
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private readonly WindowsDiagnostics diagnostics;
    private readonly HttpClient httpClient;

    public OpenAiIssueExtractionService(
        WindowsDiagnostics diagnostics,
        HttpClient? httpClient = null)
    {
        this.diagnostics = diagnostics;
        this.httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(3),
        };
    }

    public async Task<IssueExtractionResult> ExtractAsync(
        CompletedSession session,
        string apiKey,
        string model,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(session.TranscriptText))
        {
            throw new InvalidOperationException("Issue extraction requires a saved transcript.");
        }

        diagnostics.Info(
            "issue-extraction",
            $"issue extraction requested for session {session.SessionId} with model {model}");

        var payload = new ChatCompletionRequest(
            Model: model,
            Temperature: 0.1,
            ResponseFormat: new ResponseFormat("json_object"),
            Messages:
            [
                new ChatCompletionMessage(
                    "system",
                    """
                    You convert narrated software review sessions into structured, reviewable draft issues.
                    Use only information explicitly present in the transcript, screenshots, and timeline context.
                    Return strict JSON with keys summary, guidanceNote, issues.
                    Each issue must contain title, category, summary, evidenceExcerpt, timestamp, sectionTitle, relatedScreenshotFileNames, confidence, requiresReview.
                    Valid categories are exactly: Bug, UX Issue, Enhancement, Question / Follow-up.
                    Prefer conservative output. If evidence is weak, set requiresReview to true and use a lower confidence.
                    """
                ),
                new ChatCompletionMessage("user", BuildPrompt(session)),
            ]);

        using var request = new HttpRequestMessage(HttpMethod.Post, ChatCompletionsEndpoint)
        {
            Content = new StringContent(
                JsonSerializer.Serialize(payload, JsonOptions),
                Encoding.UTF8,
                "application/json"),
        };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());

        using var response = await RemoteServiceRequestGuard.SendAsync(
            httpClient,
            request,
            "OpenAI issue extraction",
            cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            diagnostics.Warning(
                "issue-extraction",
                $"issue extraction request failed with HTTP {(int)response.StatusCode}");
            throw new InvalidOperationException(BuildFailureMessage(response.StatusCode, responseBody));
        }

        var content = ExtractMessageContent(responseBody);
        if (string.IsNullOrWhiteSpace(content))
        {
            diagnostics.Warning("issue-extraction", "issue extraction response was empty");
            throw new InvalidOperationException("OpenAI returned an empty issue extraction response.");
        }

        try
        {
            var screenshotIndex = session.Screenshots
                .Select(screenshot => new
                {
                    Key = Path.GetFileName(screenshot.RelativePath).Trim().ToLowerInvariant(),
                    screenshot.ScreenshotId,
                })
                .Where(item => item.Key.Length > 0)
                .GroupBy(item => item.Key)
                .ToDictionary(group => group.Key, group => group.First().ScreenshotId);

            var result = IssueExtractionResponseParser.Parse(content, screenshotIndex);
            diagnostics.Info(
                "issue-extraction",
                $"issue extraction succeeded with {result.Issues.Count} draft issue(s)");
            return result;
        }
        catch (Exception exception)
        {
            diagnostics.Error("issue-extraction", "issue extraction response parsing failed", exception);
            throw new InvalidOperationException(
                "OpenAI returned issue data in an unexpected format. Try again, or switch the issue extraction model in Settings.");
        }
    }

    private static string BuildPrompt(CompletedSession session)
    {
        var lines = new List<string>
        {
            "Session metadata:",
            $"- Title: {session.Title}",
            $"- Recorded: {session.CreatedAt:yyyy-MM-dd HH:mm:ss zzz}",
            $"- Duration: {SessionTimeFormatter.FormatDuration(session.Duration)}",
            $"- Transcript model: {session.TranscriptionModel}",
            $"- Screenshot count: {session.Screenshots.Count}",
            "",
            "Timeline moments:",
        };

        if (session.TimelineMoments.Count == 0)
        {
            lines.Add("- None");
        }
        else
        {
            foreach (var moment in session.TimelineMoments.OrderBy(moment => moment.ElapsedSeconds))
            {
                lines.Add(
                    $"- {moment.Label} at {SessionTimeFormatter.FormatElapsedSeconds(moment.ElapsedSeconds)} ({moment.Kind})");
            }
        }

        lines.Add(string.Empty);
        lines.Add("Screenshots:");

        if (session.Screenshots.Count == 0)
        {
            lines.Add("- None");
        }
        else
        {
            foreach (var screenshot in session.Screenshots.OrderBy(screenshot => screenshot.ElapsedSeconds))
            {
                lines.Add(
                    $"- {Path.GetFileName(screenshot.RelativePath)} at {SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)}");
            }
        }

        lines.Add(string.Empty);
        lines.Add("Transcript:");
        lines.Add(session.TranscriptText.Trim());
        lines.Add(string.Empty);
        lines.Add("Return a concise summary plus reviewable draft issues for product and engineering triage.");

        return string.Join(Environment.NewLine, lines);
    }

    private static string BuildFailureMessage(HttpStatusCode statusCode, string responseBody)
    {
        var apiMessage = TryReadApiMessage(responseBody);
        if (!string.IsNullOrWhiteSpace(apiMessage))
        {
            return apiMessage!;
        }

        return statusCode switch
        {
            HttpStatusCode.Unauthorized => "The OpenAI API key was rejected for issue extraction.",
            HttpStatusCode.Forbidden => "The OpenAI issue extraction request was forbidden.",
            _ => $"OpenAI issue extraction failed with HTTP {(int)statusCode}.",
        };
    }

    private static string? TryReadApiMessage(string responseBody)
    {
        if (string.IsNullOrWhiteSpace(responseBody))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(responseBody);
            if (document.RootElement.TryGetProperty("error", out var errorElement)
                && errorElement.TryGetProperty("message", out var messageElement))
            {
                return messageElement.GetString()?.Trim();
            }
        }
        catch
        {
            // Fall back to the HTTP status mapping when the response body is not parseable JSON.
        }

        return null;
    }

    private static string? ExtractMessageContent(string responseBody)
    {
        using var document = JsonDocument.Parse(responseBody);
        if (!document.RootElement.TryGetProperty("choices", out var choicesElement)
            || choicesElement.ValueKind != JsonValueKind.Array
            || choicesElement.GetArrayLength() == 0)
        {
            throw new InvalidOperationException("OpenAI returned an invalid issue extraction response.");
        }

        var messageElement = choicesElement[0].GetProperty("message");
        if (!messageElement.TryGetProperty("content", out var contentElement))
        {
            return null;
        }

        return contentElement.ValueKind switch
        {
            JsonValueKind.String => contentElement.GetString()?.Trim(),
            JsonValueKind.Array => string.Concat(
                    contentElement.EnumerateArray()
                        .Where(item => item.ValueKind == JsonValueKind.Object
                                       && item.TryGetProperty("text", out _))
                        .Select(item => item.GetProperty("text").GetString()))
                .Trim(),
            _ => null,
        };
    }

    private sealed record ChatCompletionRequest(
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("temperature")] double Temperature,
        [property: JsonPropertyName("response_format")] ResponseFormat ResponseFormat,
        [property: JsonPropertyName("messages")] IReadOnlyList<ChatCompletionMessage> Messages);

    private sealed record ResponseFormat(
        [property: JsonPropertyName("type")] string Type);

    private sealed record ChatCompletionMessage(
        [property: JsonPropertyName("role")] string Role,
        [property: JsonPropertyName("content")] string Content);
}
