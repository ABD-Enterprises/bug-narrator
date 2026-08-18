using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// Renders the review output (<c>summary.md</c>) for a completed session.
///
/// macOS exports a <c>summary.md</c> too (TranscriptExporter.swift, added in #924), and writes it
/// only when issue extraction has run. Windows matches that emit condition. The two documents do NOT
/// yet share a byte-for-byte contract: macOS groups issues by category, while Windows renders the
/// richer per-issue detail it collects (reproduction steps, note, export selection). Converging them
/// needs a macOS renderer change and is tracked separately — see #1006.
/// </summary>
public static class CompletedSessionReviewMarkdownBuilder
{
    /// <summary>
    /// macOS writes <c>summary.md</c> only when extraction produced output; a bare review summary
    /// does not earn a file on either platform. The summary text itself is still kept in
    /// <c>session.json</c> and shown in the session library.
    /// </summary>
    public static bool HasReviewOutput(CompletedSession session)
    {
        return session.IssueExtraction is not null;
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

        if (session.IssueExtraction is null)
        {
            // Kept for callers that render a session without extraction; the exporter no longer
            // writes a file in that case (see HasReviewOutput).
            lines.Add(string.Empty);
            lines.Add("Issue extraction has not been run for this session yet.");

            return SessionMarkdown.Join(lines);
        }

        // The summary body is the extraction's own summary, matching macOS. session.ReviewSummary is
        // a different value (the stop-time status text) and is not this document's subject.
        lines.Add(string.Empty);
        lines.Add("## Summary");
        lines.Add(string.Empty);
        lines.Add(string.IsNullOrWhiteSpace(session.IssueExtraction.Summary)
            ? "No summary generated."
            : session.IssueExtraction.Summary.Trim());

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
