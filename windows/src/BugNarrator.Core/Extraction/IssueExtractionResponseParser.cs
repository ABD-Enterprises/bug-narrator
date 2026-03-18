using System.Text.Json;
using BugNarrator.Core.Models;

namespace BugNarrator.Core.Extraction;

public static class IssueExtractionResponseParser
{
    private const string DefaultGuidanceNote = "Extracted issues are draft suggestions and should be reviewed before export.";

    public static IssueExtractionResult Parse(
        string content,
        IReadOnlyDictionary<string, Guid> screenshotIndex)
    {
        var errors = new List<string>();

        foreach (var candidate in GetJsonCandidates(content))
        {
            try
            {
                return ParseCandidate(candidate, screenshotIndex);
            }
            catch (Exception exception)
            {
                errors.Add(exception.Message);
            }
        }

        throw new InvalidOperationException(
            $"OpenAI returned issue data in an unexpected format. {string.Join(" | ", errors)}");
    }

    private static IssueExtractionResult ParseCandidate(
        string candidate,
        IReadOnlyDictionary<string, Guid> screenshotIndex)
    {
        using var document = JsonDocument.Parse(candidate);
        if (document.RootElement.ValueKind != JsonValueKind.Object)
        {
            throw new InvalidOperationException("Top-level issue extraction payload was not a JSON object.");
        }

        var root = document.RootElement;
        var summary = GetFirstString(root, "summary", "reviewSummary", "review_summary");
        var guidanceNote = GetFirstString(root, "guidanceNote", "guidance_note", "reviewGuidance", "review_guidance");
        var issueElements = GetFirstArray(root, "issues", "draftIssues", "draft_issues", "items");

        var issues = new List<ExtractedIssue>();
        if (issueElements is not null)
        {
            foreach (var issueElement in issueElements.Value.EnumerateArray())
            {
                if (TryParseIssue(issueElement, screenshotIndex, out var issue))
                {
                    issues.Add(issue!);
                }
            }
        }

        if (summary is null && guidanceNote is null && issues.Count == 0)
        {
            throw new InvalidOperationException("Issue extraction payload did not contain a summary, guidance note, or issues.");
        }

        if (issueElements is not null && issueElements.Value.GetArrayLength() > 0 && issues.Count == 0)
        {
            throw new InvalidOperationException("Issue extraction payload contained issues, but none matched the expected structure.");
        }

        return new IssueExtractionResult(
            GeneratedAt: DateTimeOffset.UtcNow,
            Summary: summary?.Trim() ?? string.Empty,
            GuidanceNote: string.IsNullOrWhiteSpace(guidanceNote) ? DefaultGuidanceNote : guidanceNote.Trim(),
            Issues: issues);
    }

    private static bool TryParseIssue(
        JsonElement issueElement,
        IReadOnlyDictionary<string, Guid> screenshotIndex,
        out ExtractedIssue? issue)
    {
        issue = null;
        if (issueElement.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        var title = GetFirstString(issueElement, "title", "issueTitle", "name");
        var category = GetFirstString(issueElement, "category", "type", "classification");
        var summary = GetFirstString(issueElement, "summary", "description", "details");
        var evidenceExcerpt = GetFirstString(issueElement, "evidenceExcerpt", "evidence", "evidenceQuote", "evidence_excerpt");

        if (string.IsNullOrWhiteSpace(title)
            || string.IsNullOrWhiteSpace(category)
            || string.IsNullOrWhiteSpace(summary)
            || string.IsNullOrWhiteSpace(evidenceExcerpt))
        {
            return false;
        }

        var relatedScreenshotIds = GetFirstStringArray(
                issueElement,
                "relatedScreenshotFileNames",
                "screenshotFileNames",
                "screenshots",
                "related_screenshot_file_names")
            .Select(fileName => fileName.Trim().ToLowerInvariant())
            .Where(screenshotIndex.ContainsKey)
            .Select(fileName => screenshotIndex[fileName])
            .ToArray();

        issue = new ExtractedIssue(
            IssueId: Guid.NewGuid(),
            Title: title.Trim(),
            Category: ParseCategory(category),
            Summary: summary.Trim(),
            EvidenceExcerpt: evidenceExcerpt.Trim(),
            TimestampSeconds: ParseTimestamp(GetFirstValue(issueElement, "timestamp", "time", "timecode")),
            RelatedScreenshotIds: relatedScreenshotIds,
            Confidence: GetFirstDouble(issueElement, "confidence", "score"),
            RequiresReview: GetFirstBool(issueElement, "requiresReview", "requires_review", "needsReview") ?? true,
            IsSelectedForExport: true,
            SectionTitle: GetFirstString(issueElement, "sectionTitle", "section", "sectionName")?.Trim(),
            Note: GetFirstString(issueElement, "note", "comment")?.Trim());
        return true;
    }

    private static ExtractedIssueCategory ParseCategory(string rawValue)
    {
        return rawValue.Trim().ToLowerInvariant() switch
        {
            "bug" => ExtractedIssueCategory.Bug,
            "ux issue" or "ux" or "usability" => ExtractedIssueCategory.UxIssue,
            "enhancement" or "enhancement request" => ExtractedIssueCategory.Enhancement,
            _ => ExtractedIssueCategory.FollowUp,
        };
    }

    private static double? ParseTimestamp(JsonElement? element)
    {
        if (element is null)
        {
            return null;
        }

        if (element.Value.ValueKind == JsonValueKind.Number && element.Value.TryGetDouble(out var numericValue))
        {
            return numericValue;
        }

        if (element.Value.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        var rawValue = element.Value.GetString()?.Trim();
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            return null;
        }

        if (double.TryParse(rawValue, out var seconds))
        {
            return seconds;
        }

        var parts = rawValue.Split(':', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(part => double.TryParse(part, out var value) ? value : double.NaN)
            .ToArray();

        if (parts.Any(double.IsNaN))
        {
            return null;
        }

        return parts.Length switch
        {
            2 => (parts[0] * 60) + parts[1],
            3 => (parts[0] * 3600) + (parts[1] * 60) + parts[2],
            _ => null,
        };
    }

    private static IEnumerable<string> GetJsonCandidates(string content)
    {
        var trimmed = content.Trim();
        var seen = new HashSet<string>(StringComparer.Ordinal);

        void AddCandidate(List<string> candidates, string? value)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                return;
            }

            var normalized = value.Trim();
            if (seen.Add(normalized))
            {
                candidates.Add(normalized);
            }
        }

        var candidates = new List<string>();
        AddCandidate(candidates, trimmed);

        if (trimmed.StartsWith("```", StringComparison.Ordinal))
        {
            var lines = trimmed.Split('\n');
            if (lines.Length >= 3)
            {
                var body = string.Join('\n', lines.Skip(1).Take(lines.Length - 2));
                AddCandidate(candidates, body);
            }
        }

        var firstObjectStart = trimmed.IndexOf('{');
        var lastObjectEnd = trimmed.LastIndexOf('}');
        if (firstObjectStart >= 0 && lastObjectEnd > firstObjectStart)
        {
            AddCandidate(candidates, trimmed[firstObjectStart..(lastObjectEnd + 1)]);
        }

        return candidates;
    }

    private static JsonElement? GetFirstArray(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (element.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.Array)
            {
                return value;
            }
        }

        return null;
    }

    private static JsonElement? GetFirstValue(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (element.TryGetProperty(propertyName, out var value))
            {
                return value;
            }
        }

        return null;
    }

    private static string? GetFirstString(JsonElement element, params string[] propertyNames)
    {
        var value = GetFirstValue(element, propertyNames);
        return value is { ValueKind: JsonValueKind.String }
            ? value.Value.GetString()
            : null;
    }

    private static double? GetFirstDouble(JsonElement element, params string[] propertyNames)
    {
        var value = GetFirstValue(element, propertyNames);
        if (value is null)
        {
            return null;
        }

        return value.Value.ValueKind switch
        {
            JsonValueKind.Number when value.Value.TryGetDouble(out var number) => number,
            JsonValueKind.String when double.TryParse(value.Value.GetString(), out var number) => number,
            _ => null,
        };
    }

    private static bool? GetFirstBool(JsonElement element, params string[] propertyNames)
    {
        var value = GetFirstValue(element, propertyNames);
        if (value is null)
        {
            return null;
        }

        return value.Value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => null,
        };
    }

    private static IReadOnlyList<string> GetFirstStringArray(JsonElement element, params string[] propertyNames)
    {
        var value = GetFirstValue(element, propertyNames);
        if (value is null || value.Value.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<string>();
        }

        return value.Value.EnumerateArray()
            .Where(item => item.ValueKind == JsonValueKind.String)
            .Select(item => item.GetString() ?? string.Empty)
            .Where(item => !string.IsNullOrWhiteSpace(item))
            .ToArray();
    }
}
