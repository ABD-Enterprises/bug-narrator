using BugNarrator.Core.Extraction;
using BugNarrator.Core.Models;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class IssueExtractionResponseParserTests
{
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
