using BugNarrator.Core.Extraction;
using BugNarrator.Core.Models;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class IssueExtractionResponseParserTests
{
    [Fact]
    public void Parse_ReadsSeverityComponentAndDeduplicationHint()
    {
        var content =
            """
            {
              "summary": "One issue.",
              "issues": [
                {
                  "title": "Save button clips",
                  "category": "Bug",
                  "severity": "High",
                  "component": "Save flow",
                  "summary": "The save button is clipped.",
                  "evidenceExcerpt": "clipped",
                  "deduplicationHint": "save-button-clipping"
                }
              ]
            }
            """;

        var issue = Assert.Single(
            IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()).Issues);

        Assert.Equal(ExtractedIssueSeverity.High, issue.Severity);
        Assert.Equal("Save flow", issue.Component);
        Assert.Equal("save-button-clipping", issue.DeduplicationHint);
        Assert.Equal("save-button-clipping", issue.EffectiveDeduplicationHint);
    }

    [Fact]
    public void Parse_UsesMacAliasKeysForTheNewFields()
    {
        var content =
            """
            {
              "issues": [
                {
                  "title": "Slow export",
                  "category": "Bug",
                  "priority": "Critical",
                  "affected_component": "Export",
                  "summary": "Export takes minutes.",
                  "evidenceExcerpt": "took two minutes",
                  "dedup_hint": "slow-export"
                }
              ]
            }
            """;

        var issue = Assert.Single(
            IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()).Issues);

        Assert.Equal(ExtractedIssueSeverity.Critical, issue.Severity);
        Assert.Equal("Export", issue.Component);
        Assert.Equal("slow-export", issue.DeduplicationHint);
    }

    [Fact]
    public void Parse_FallsBackSafelyWhenNewFieldsAreMissingOrInvalid()
    {
        var content =
            """
            {
              "issues": [
                {
                  "title": "Missing fields",
                  "category": "Bug",
                  "severity": "catastrophic",
                  "component": "   ",
                  "summary": "No severity given.",
                  "evidenceExcerpt": "evidence"
                }
              ]
            }
            """;

        var issue = Assert.Single(
            IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()).Issues);

        // An unusable value must never drop an otherwise valid issue.
        Assert.Equal(ExtractedIssueSeverity.Medium, issue.Severity);
        Assert.Null(issue.Component);
        Assert.Null(issue.DeduplicationHint);
        Assert.StartsWith("issue-", issue.EffectiveDeduplicationHint);
    }

    [Fact]
    public void IssueDeduplication_MatchesTheMacHashContract()
    {
        // Same normalization + FNV-1a 64 as macOS makeDeduplicationHint, so the same issue yields
        // the same hint on both platforms.
        var hint = IssueDeduplication.MakeHint("Save button clips", "It is clipped.", "clipped");

        Assert.Matches("^issue-[0-9a-f]{16}$", hint);

        // Case, diacritics, and whitespace runs must not change the identity.
        Assert.Equal(
            hint,
            IssueDeduplication.MakeHint("SAVE   button  clips", "It is clipped.", "clipped"));
        Assert.Equal("issue-0000000000000000", IssueDeduplication.MakeHint("", "", ""));
        Assert.NotEqual(hint, IssueDeduplication.MakeHint("Different", "It is clipped.", "clipped"));
    }

    [Fact]
    public void Parse_HandlesMarkdownFenceAliasKeysAndScreenshotMapping()
    {
        var screenshotId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        var content =
            """
            ```json
            {
              "reviewSummary": "One draft issue was extracted.",
              "guidance_note": "Review before export.",
              "draftIssues": [
                {
                  "issueTitle": "Save button clips in the modal",
                  "type": "Bug",
                  "description": "The save button appears clipped in the modal layout.",
                  "evidence": "The save button is clipped",
                  "timecode": "00:08",
                  "section": "Save flow",
                  "screenshotFileNames": ["review-shot.png"],
                  "score": 0.74,
                  "needsReview": true
                }
              ]
            }
            ```
            """;

        var result = IssueExtractionResponseParser.Parse(
            content,
            new Dictionary<string, Guid>(StringComparer.OrdinalIgnoreCase)
            {
                ["review-shot.png"] = screenshotId,
            });

        var issue = Assert.Single(result.Issues);
        Assert.Equal("One draft issue was extracted.", result.Summary);
        Assert.Equal("Review before export.", result.GuidanceNote);
        Assert.Equal("Save button clips in the modal", issue.Title);
        Assert.Equal(ExtractedIssueCategory.Bug, issue.Category);
        Assert.Equal(8, issue.TimestampSeconds);
        Assert.Equal([screenshotId], issue.RelatedScreenshotIds);
    }

    [Fact]
    public void Parse_ThrowsWhenStructuredIssuesDoNotMatchExpectedShape()
    {
        var content =
            """
            {
              "summary": "One draft issue was extracted.",
              "issues": [
                {
                  "category": "Bug"
                }
              ]
            }
            """;

        var exception = Assert.Throws<InvalidOperationException>(() =>
            IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()));

        Assert.Contains("unexpected format", exception.Message, StringComparison.OrdinalIgnoreCase);
    }
}
