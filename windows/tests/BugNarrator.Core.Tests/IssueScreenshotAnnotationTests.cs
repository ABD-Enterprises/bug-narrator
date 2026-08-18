using BugNarrator.Core.Extraction;
using BugNarrator.Core.Models;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class IssueScreenshotAnnotationTests
{
    private static readonly Guid ScreenshotId = Guid.Parse("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee");

    private static Dictionary<string, Guid> Index() =>
        new(StringComparer.OrdinalIgnoreCase) { ["shot.png"] = ScreenshotId };

    [Fact]
    public void Constructor_ClampsExactlyLikeMac()
    {
        // Oversized rectangle: size clamps to 1, which forces the origin to 0.
        var huge = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, null, x: 5, y: 5, width: 9, height: 9);
        Assert.Equal(1, huge.Width);
        Assert.Equal(1, huge.Height);
        Assert.Equal(0, huge.X);
        Assert.Equal(0, huge.Y);

        // Below the 0.05 minimum extent macOS enforces.
        var tiny = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, null, x: 0.5, y: 0.5, width: 0, height: -1);
        Assert.Equal(0.05, tiny.Width);
        Assert.Equal(0.05, tiny.Height);

        // The origin is bounded by 1 - size so the rectangle stays inside the image.
        var overflowing = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, null, x: 0.9, y: 0.95, width: 0.5, height: 0.5);
        Assert.Equal(0.5, overflowing.X);
        Assert.Equal(0.5, overflowing.Y);
        Assert.True(overflowing.X + overflowing.Width <= 1.0);
        Assert.True(overflowing.Y + overflowing.Height <= 1.0);
    }

    [Fact]
    public void Constructor_TrimsLabelToNullWhenBlank()
    {
        Assert.Null(new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, "   ", 0, 0, 0.5, 0.5).Label);
        Assert.Equal("Save button", new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, "  Save button  ", 0, 0, 0.5, 0.5).Label);
    }

    [Fact]
    public void ExportDescription_MatchesTheMacShape()
    {
        var withLabel = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, "Save button", 0.1, 0.2, 0.3, 0.4, confidence: 0.85);
        Assert.Equal("Save button • x 10% • y 20% • w 30% • h 40% • confidence 85%", withLabel.ExportDescription);

        // Swift .rounded() rounds halves away from zero: 0.845 is 85%, not banker's-rounded 84%.
        var tie = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, "Tie", 0.1, 0.2, 0.3, 0.4, confidence: 0.845);
        Assert.Equal("85%", tie.ConfidenceLabel);

        // macOS substitutes "UI highlight" when the model gives no label, and omits confidence.
        var bare = new IssueScreenshotAnnotation(
            Guid.NewGuid(), ScreenshotId, null, 0.1, 0.2, 0.3, 0.4);
        Assert.Equal("UI highlight • x 10% • y 20% • w 30% • h 40%", bare.ExportDescription);
    }

    [Fact]
    public void Parse_ReadsAnnotationsWithMacAliasKeys()
    {
        var content =
            """
            {
              "issues": [
                {
                  "title": "Save clips", "category": "Bug", "summary": "s", "evidenceExcerpt": "e",
                  "annotations": [
                    { "left": 0.1, "top": 0.2, "w": 0.3, "h": 0.4,
                      "title": "Save button", "score": 0.5, "screenshotFileName": "shot.png" }
                  ]
                }
              ]
            }
            """;

        var issue = Assert.Single(IssueExtractionResponseParser.Parse(content, Index()).Issues);
        var annotation = Assert.Single(issue.ScreenshotAnnotations);

        Assert.Equal(ScreenshotId, annotation.ScreenshotId);
        Assert.Equal("Save button", annotation.Label);
        Assert.Equal(0.1, annotation.X, precision: 6);
        Assert.Equal(0.3, annotation.Width, precision: 6);
        Assert.Equal("50%", annotation.ConfidenceLabel);
        Assert.Equal(IssueScreenshotAnnotationStyle.Highlight, annotation.Style);
    }

    [Fact]
    public void Parse_FallsBackToTheIssuesFirstRelatedScreenshot()
    {
        // macOS uses screenshotIDs.first when the annotation names no screenshot.
        var content =
            """
            {
              "issues": [
                {
                  "title": "t", "category": "Bug", "summary": "s", "evidenceExcerpt": "e",
                  "relatedScreenshotFileNames": ["shot.png"],
                  "screenshotAnnotations": [ { "x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2 } ]
                }
              ]
            }
            """;

        var issue = Assert.Single(IssueExtractionResponseParser.Parse(content, Index()).Issues);
        Assert.Equal(ScreenshotId, Assert.Single(issue.ScreenshotAnnotations).ScreenshotId);
    }

    [Fact]
    public void Parse_SkipsUnusableAnnotationsWithoutDroppingTheIssue()
    {
        var content =
            """
            {
              "issues": [
                {
                  "title": "Still valid", "category": "Bug", "summary": "s", "evidenceExcerpt": "e",
                  "screenshotAnnotations": [
                    { "x": 0.1, "y": 0.1, "width": 0.2 },
                    { "y": 0.1, "width": 0.2, "height": 0.2, "screenshot": "shot.png" },
                    "not an object",
                    42,
                    { "x": 0.1, "y": 0.1, "width": 0.2, "height": 0.2, "screenshot": "shot.png" }
                  ]
                }
              ]
            }
            """;

        var issue = Assert.Single(IssueExtractionResponseParser.Parse(content, Index()).Issues);

        // Missing height, missing x, and non-objects are skipped individually; the one usable
        // annotation survives and the issue is never dropped.
        Assert.Single(issue.ScreenshotAnnotations);
        Assert.Equal("Still valid", issue.Title);
    }

    [Fact]
    public void Parse_DefaultsToEmptyWhenAbsentOrNotAnArray()
    {
        foreach (var content in new[]
        {
            """{ "issues": [ { "title": "t", "category": "Bug", "summary": "s", "evidenceExcerpt": "e" } ] }""",
            """{ "issues": [ { "title": "t", "category": "Bug", "summary": "s", "evidenceExcerpt": "e", "screenshotAnnotations": "nope" } ] }""",
        })
        {
            var issue = Assert.Single(IssueExtractionResponseParser.Parse(content, Index()).Issues);
            Assert.Empty(issue.ScreenshotAnnotations);
        }
    }

    [Fact]
    public void Deserialization_GoesThroughTheClampingConstructor()
    {
        // The class has get-only properties and one constructor, so System.Text.Json must construct
        // it through that constructor. If it ever gained a parameterless ctor or settable
        // properties, a tampered session.json could load an out-of-bounds rectangle — this is the
        // test that would catch it.
        var json =
            """
            {
              "AnnotationId": "66666666-6666-6666-6666-666666666666",
              "ScreenshotId": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
              "Label": "  Tampered  ",
              "X": 9,
              "Y": -4,
              "Width": 0,
              "Height": 50,
              "Confidence": null,
              "Style": 0
            }
            """;

        var annotation = System.Text.Json.JsonSerializer.Deserialize<IssueScreenshotAnnotation>(json);

        Assert.NotNull(annotation);
        Assert.Equal(0.05, annotation!.Width);
        Assert.Equal(1, annotation.Height);
        Assert.InRange(annotation.X, 0, 1 - annotation.Width);
        Assert.Equal(0, annotation.Y);
        Assert.Equal("Tampered", annotation.Label);
    }

    [Fact]
    public void ExtractedIssue_RoundTripsAnnotationsThroughSessionJson()
    {
        var original = new ExtractedIssue(
            IssueId: Guid.NewGuid(),
            Title: "t",
            Category: ExtractedIssueCategory.Bug,
            Summary: "s",
            EvidenceExcerpt: "e",
            TimestampSeconds: null,
            RelatedScreenshotIds: [],
            Confidence: null,
            RequiresReview: true,
            IsSelectedForExport: true,
            SectionTitle: null,
            Note: null)
        {
            ScreenshotAnnotations =
            [
                new IssueScreenshotAnnotation(
                    Guid.NewGuid(), ScreenshotId, "Save button", 0.1, 0.2, 0.3, 0.4, 0.85),
            ],
        };

        var json = System.Text.Json.JsonSerializer.Serialize(original);
        var restored = System.Text.Json.JsonSerializer.Deserialize<ExtractedIssue>(json);

        var annotation = Assert.Single(restored!.ScreenshotAnnotations);
        Assert.Equal("Save button", annotation.Label);
        Assert.Equal(0.1, annotation.X, precision: 6);
        Assert.Equal(0.4, annotation.Height, precision: 6);
        Assert.Equal("85%", annotation.ConfidenceLabel);
    }

    [Fact]
    public void ExtractedIssue_DeserializesSessionJsonSavedBeforeAnnotationsExisted()
    {
        // Property casing mirrors FileCompletedSessionStore's serializer options (defaults).
        var json =
            """
            {
              "IssueId": "55555555-5555-5555-5555-555555555555",
              "Title": "Save button clips",
              "Category": 0,
              "Summary": "s",
              "EvidenceExcerpt": "e",
              "TimestampSeconds": null,
              "RelatedScreenshotIds": [],
              "Confidence": null,
              "RequiresReview": true,
              "IsSelectedForExport": true,
              "SectionTitle": null,
              "Note": null
            }
            """;

        var issue = System.Text.Json.JsonSerializer.Deserialize<ExtractedIssue>(json);

        Assert.NotNull(issue);
        Assert.Empty(issue!.ScreenshotAnnotations);
    }
}
