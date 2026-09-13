using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>The four review workspace tabs, in the order the product spec lists them.</summary>
public enum ReviewWorkspaceTab
{
    Transcript = 0,
    Screenshots = 1,
    ExtractedIssues = 2,
    Summary = 3,
}

/// <summary>
/// Which tab the review workspace should land on after an action. Pure so it can be tested with no
/// window; the window applies the result. The product spec's rule (docs/architecture/product-spec.md,
/// "Session Library And Review Workspace"): if issue extraction returns no draft issues, fall back to
/// <see cref="ReviewWorkspaceTab.Summary"/> instead of leaving an empty extracted-issues view selected.
/// </summary>
public static class ReviewWorkspaceTabPolicy
{
    /// <summary>
    /// The tab to select after extraction has <em>completed</em>. Callers must apply this only on the
    /// success path — a thrown extraction never reaches here, which is what keeps the current tab in
    /// place on failure.
    /// </summary>
    public static ReviewWorkspaceTab AfterExtraction(IssueExtractionResult result)
    {
        return result.Issues.Count == 0
            ? ReviewWorkspaceTab.Summary
            : ReviewWorkspaceTab.ExtractedIssues;
    }
}
