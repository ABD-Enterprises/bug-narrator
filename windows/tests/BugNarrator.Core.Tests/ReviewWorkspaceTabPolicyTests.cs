using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class ReviewWorkspaceTabPolicyTests
{
    [Fact]
    public void AfterExtraction_WithNoDraftIssues_FallsBackToSummary()
    {
        var result = Result(issueCount: 0);

        Assert.Equal(ReviewWorkspaceTab.Summary, ReviewWorkspaceTabPolicy.AfterExtraction(result));
    }

    [Theory]
    [InlineData(1)]
    [InlineData(7)]
    public void AfterExtraction_WithDraftIssues_LandsOnExtractedIssues(int issueCount)
    {
        var result = Result(issueCount);

        Assert.Equal(ReviewWorkspaceTab.ExtractedIssues, ReviewWorkspaceTabPolicy.AfterExtraction(result));
    }

    [Fact]
    public void TabOrder_MatchesTheSpecAndTheWindowIndices()
    {
        // The window applies the enum value as TabControl.SelectedIndex, so the order is load-bearing.
        Assert.Equal(0, (int)ReviewWorkspaceTab.Transcript);
        Assert.Equal(1, (int)ReviewWorkspaceTab.Screenshots);
        Assert.Equal(2, (int)ReviewWorkspaceTab.ExtractedIssues);
        Assert.Equal(3, (int)ReviewWorkspaceTab.Summary);
    }

    private static IssueExtractionResult Result(int issueCount)
    {
        var issues = Enumerable.Range(0, issueCount)
            .Select(index => new ExtractedIssue(
                IssueId: Guid.NewGuid(),
                Title: $"Issue {index}",
                Category: ExtractedIssueCategory.Bug,
                Summary: "A summary.",
                EvidenceExcerpt: "Evidence.",
                TimestampSeconds: index,
                RelatedScreenshotIds: [],
                Confidence: 0.8,
                RequiresReview: true,
                IsSelectedForExport: true,
                SectionTitle: null,
                Note: null))
            .ToArray();

        return new IssueExtractionResult(
            GeneratedAt: DateTimeOffset.UtcNow,
            Summary: "Summary.",
            GuidanceNote: "Guidance.",
            Issues: issues);
    }
}
