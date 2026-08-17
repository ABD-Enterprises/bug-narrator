using BugNarrator.Core.Export;
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
    public void Parse_ReadsReproductionStepsIncludingScreenshotReference()
    {
        var screenshotId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");
        var content =
            """
            {
              "issues": [
                {
                  "title": "Checkout clips",
                  "category": "Bug",
                  "summary": "Clipped at 1280.",
                  "evidenceExcerpt": "clipped",
                  "reproductionSteps": [
                    {
                      "instruction": "Open checkout",
                      "expectedResult": "Button fully visible",
                      "actualResult": "Right edge cut off",
                      "timestamp": "00:30",
                      "screenshotFileName": "shot.png"
                    },
                    { "step": "Resize to 1280 wide" }
                  ]
                }
              ]
            }
            """;

        var issue = Assert.Single(IssueExtractionResponseParser.Parse(
            content,
            new Dictionary<string, Guid>(StringComparer.OrdinalIgnoreCase) { ["shot.png"] = screenshotId }).Issues);

        Assert.Equal(2, issue.ReproductionSteps.Count);

        var first = issue.ReproductionSteps[0];
        Assert.Equal("Open checkout", first.Instruction);
        Assert.Equal("Button fully visible", first.ExpectedResult);
        Assert.Equal("Right edge cut off", first.ActualResult);
        Assert.Equal(30, first.TimestampSeconds);
        Assert.Equal("00:30", first.TimestampLabel);
        Assert.Equal(screenshotId, first.ScreenshotId);

        // Alias key, and everything optional absent.
        Assert.Equal("Resize to 1280 wide", issue.ReproductionSteps[1].Instruction);
        Assert.Null(issue.ReproductionSteps[1].ExpectedResult);
        Assert.Null(issue.ReproductionSteps[1].ScreenshotId);
    }

    [Fact]
    public void Parse_ToleratesMalformedReproductionStepsWithoutDroppingTheIssue()
    {
        var content =
            """
            {
              "issues": [
                {
                  "title": "Still valid",
                  "category": "Bug",
                  "summary": "Summary.",
                  "evidenceExcerpt": "evidence",
                  "stepsToReproduce": [
                    "A plain string step",
                    { "instruction": "   " },
                    { "noInstructionHere": "ignored" },
                    { "instruction": 42 },
                    42,
                    { "instruction": "Real step", "screenshotFileName": "missing.png" }
                  ]
                }
              ]
            }
            """;

        var issue = Assert.Single(
            IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()).Issues);

        // Plain-string and well-formed entries survive; blank/typeless/non-object entries are skipped.
        Assert.Equal(2, issue.ReproductionSteps.Count);
        Assert.Equal("A plain string step", issue.ReproductionSteps[0].Instruction);
        Assert.Equal("Real step", issue.ReproductionSteps[1].Instruction);
        // An unknown screenshot name must not invent a reference.
        Assert.Null(issue.ReproductionSteps[1].ScreenshotId);
    }

    [Fact]
    public void Parse_DefaultsReproductionStepsToEmptyWhenAbsentOrNotAnArray()
    {
        var absent =
            """
            { "issues": [ { "title": "T", "category": "Bug", "summary": "S", "evidenceExcerpt": "E" } ] }
            """;
        var notAnArray =
            """
            { "issues": [ { "title": "T", "category": "Bug", "summary": "S", "evidenceExcerpt": "E", "reproductionSteps": "nope" } ] }
            """;

        foreach (var content in new[] { absent, notAnArray })
        {
            var issue = Assert.Single(
                IssueExtractionResponseParser.Parse(content, new Dictionary<string, Guid>()).Issues);
            Assert.Empty(issue.ReproductionSteps);
        }
    }

    [Fact]
    public void TrackerExportPayloadBudget_TruncatesAndMarksOmissions()
    {
        var longText = new string('x', 600);
        var truncated = TrackerExportPayloadBudget.Truncated(longText, TrackerExportPayloadBudget.ListEntryLimit);

        // Pin the exact marker, including the leading space and the U+2026 ellipsis: macOS uses this
        // byte-for-byte, and a marker that merely "ends with" the bracket text could still diverge.
        const string marker = " …[truncated by BugNarrator for tracker limits]";
        Assert.EndsWith(marker, truncated);
        // macOS reserves 36 characters for the marker before cutting.
        Assert.Equal(new string('x', TrackerExportPayloadBudget.ListEntryLimit - 36) + marker, truncated);

        // Short values pass through untouched.
        Assert.Equal("short", TrackerExportPayloadBudget.Truncated("  short  ", 100));
        // A value exactly at the cap is not truncated.
        Assert.Equal(new string('y', 100), TrackerExportPayloadBudget.Truncated(new string('y', 100), 100));

        var many = Enumerable.Range(1, 12).Select(i => $"step {i}").ToArray();
        var limited = TrackerExportPayloadBudget.LimitedList(many, TrackerExportPayloadBudget.ReproductionStepLimit, 100);

        Assert.Equal(TrackerExportPayloadBudget.ReproductionStepLimit + 1, limited.Count);
        Assert.Equal("Additional items were omitted by BugNarrator to fit tracker limits.", limited[^1]);
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
