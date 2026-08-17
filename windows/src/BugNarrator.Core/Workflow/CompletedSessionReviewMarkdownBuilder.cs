using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// Renders the review output (<c>summary.md</c>) for a completed session: the review summary and the
/// extracted issues that used to be appended to <c>transcript.md</c>.
///
/// This file is Windows-only. macOS defines an equivalent <c>summaryMarkdownContent</c> but never
/// exports it, so its session bundle contains no counterpart. Windows keeps the information rather
/// than dropping it when <c>transcript.md</c> moved onto the shared macOS contract.
/// </summary>
public static class CompletedSessionReviewMarkdownBuilder
{
    public static bool HasReviewOutput(CompletedSession session)
    {
        return session.IssueExtraction is not null
            || !string.IsNullOrWhiteSpace(session.ReviewSummary);
    }

    public static string Build(CompletedSession session)
    {
        return Build(session, SessionTimeFormatter.DefaultTimestampOptions);
    }

    public static string Build(CompletedSession session, SessionTimestampOptions timestampOptions)
    {
        var lines = new List<string>
        {
            "# BugNarrator Review Output",
            string.Empty,
            $"- Recorded: {SessionTimeFormatter.FormatTimestamp(session.CreatedAt, timestampOptions)}",
            $"- Duration: {SessionTimeFormatter.FormatDuration(session.Duration)}",
        };

        if (!string.IsNullOrWhiteSpace(session.TranscriptionModel))
        {
            lines.Add($"- Transcript Model: {session.TranscriptionModel}");
        }

        if (!string.IsNullOrWhiteSpace(session.ReviewSummary))
        {
            lines.Add(string.Empty);
            lines.Add("## Summary");
            lines.Add(string.Empty);
            lines.Add(session.ReviewSummary.Trim());
        }

        if (session.IssueExtraction is null)
        {
            lines.Add(string.Empty);
            lines.Add("Issue extraction has not been run for this session yet.");

            return SessionMarkdown.Join(lines);
        }

        lines.Add(string.Empty);
        lines.Add("## Extracted Issues");
        lines.Add(string.Empty);
        lines.Add($"> {session.IssueExtraction.GuidanceNote}");
        lines.Add(string.Empty);

        foreach (var issue in session.IssueExtraction.Issues)
        {
            lines.Add($"### {issue.Title}");
            lines.Add(string.Empty);
            lines.Add($"- Category: {ToDisplayText(issue.Category)}");
            lines.Add($"- Severity: {issue.Severity}");

            if (!string.IsNullOrWhiteSpace(issue.Component))
            {
                lines.Add($"- Component: {issue.Component}");
            }

            if (issue.TimestampSeconds is not null)
            {
                lines.Add($"- Transcript Time: {SessionTimeFormatter.FormatElapsedSeconds(issue.TimestampSeconds.Value)}");
            }

            if (!string.IsNullOrWhiteSpace(issue.SectionTitle))
            {
                lines.Add($"- Section: {issue.SectionTitle}");
            }

            if (issue.ConfidenceLabel is not null)
            {
                lines.Add($"- Confidence: {issue.ConfidenceLabel}");
            }

            lines.Add($"- Dedup Hint: {issue.EffectiveDeduplicationHint}");
            lines.Add($"- Requires Review: {(issue.RequiresReview ? "Yes" : "No")}");
            lines.Add($"- Selected For Export: {(issue.IsSelectedForExport ? "Yes" : "No")}");
            lines.Add(string.Empty);
            lines.Add(issue.Summary);
            lines.Add(string.Empty);
            lines.Add($"> {issue.EvidenceExcerpt}");

            if (issue.ReproductionSteps.Count > 0)
            {
                lines.Add(string.Empty);
                lines.Add("Reproduction steps:");
                lines.Add(string.Empty);

                var stepNumber = 1;
                foreach (var step in issue.ReproductionSteps)
                {
                    lines.Add($"{stepNumber}. {step.Instruction}");

                    if (!string.IsNullOrWhiteSpace(step.ExpectedResult))
                    {
                        lines.Add($"   - Expected: {step.ExpectedResult}");
                    }

                    if (!string.IsNullOrWhiteSpace(step.ActualResult))
                    {
                        lines.Add($"   - Actual: {step.ActualResult}");
                    }

                    if (step.TimestampLabel is not null)
                    {
                        lines.Add($"   - Transcript: `{step.TimestampLabel}`");
                    }

                    stepNumber++;
                }
            }

            if (!string.IsNullOrWhiteSpace(issue.Note))
            {
                lines.Add(string.Empty);
                lines.Add($"Note: {issue.Note}");
            }

            lines.Add(string.Empty);
        }

        return SessionMarkdown.Join(lines);
    }

    private static string ToDisplayText(ExtractedIssueCategory category)
    {
        return category switch
        {
            ExtractedIssueCategory.Bug => "Bug",
            ExtractedIssueCategory.UxIssue => "UX Issue",
            ExtractedIssueCategory.Enhancement => "Enhancement",
            ExtractedIssueCategory.FollowUp => "Question / Follow-up",
            _ => category.ToString(),
        };
    }
}
