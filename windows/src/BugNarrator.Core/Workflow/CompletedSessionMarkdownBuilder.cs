using System.Text;
using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public static class CompletedSessionMarkdownBuilder
{
    public static string Build(CompletedSession session)
    {
        var builder = new StringBuilder();

        builder.AppendLine("# BugNarrator Transcript");
        builder.AppendLine();
        builder.AppendLine($"- Recorded: {session.CreatedAt:yyyy-MM-dd HH:mm:ss zzz}");
        builder.AppendLine($"- Duration: {SessionTimeFormatter.FormatDuration(session.Duration)}");
        builder.AppendLine($"- Transcription Status: {ToDisplayText(session.TranscriptionStatus)}");

        if (!string.IsNullOrWhiteSpace(session.TranscriptionModel))
        {
            builder.AppendLine($"- Model: {session.TranscriptionModel}");
        }

        if (!string.IsNullOrWhiteSpace(session.LanguageHint))
        {
            builder.AppendLine($"- Language Hint: {session.LanguageHint}");
        }

        if (!string.IsNullOrWhiteSpace(session.Prompt))
        {
            builder.AppendLine($"- Prompt: {session.Prompt}");
        }

        if (!string.IsNullOrWhiteSpace(session.TranscriptionFailureMessage))
        {
            builder.AppendLine($"- Transcription Note: {session.TranscriptionFailureMessage}");
        }

        builder.AppendLine();
        builder.AppendLine("## Review Summary");
        builder.AppendLine();
        builder.AppendLine(session.ReviewSummary);
        builder.AppendLine();

        if (session.IssueExtraction is not null)
        {
            builder.AppendLine("## Extracted Issues");
            builder.AppendLine();
            builder.AppendLine($"> {session.IssueExtraction.GuidanceNote}");
            builder.AppendLine();

            foreach (var issue in session.IssueExtraction.Issues)
            {
                builder.AppendLine($"### {issue.Title}");
                builder.AppendLine();
                builder.AppendLine($"- Category: {ToDisplayText(issue.Category)}");

                if (issue.TimestampSeconds is not null)
                {
                    builder.AppendLine($"- Transcript Time: {SessionTimeFormatter.FormatElapsedSeconds(issue.TimestampSeconds.Value)}");
                }

                if (!string.IsNullOrWhiteSpace(issue.SectionTitle))
                {
                    builder.AppendLine($"- Section: {issue.SectionTitle}");
                }

                if (issue.ConfidenceLabel is not null)
                {
                    builder.AppendLine($"- Confidence: {issue.ConfidenceLabel}");
                }

                builder.AppendLine($"- Requires Review: {(issue.RequiresReview ? "Yes" : "No")}");
                builder.AppendLine($"- Selected For Export: {(issue.IsSelectedForExport ? "Yes" : "No")}");
                builder.AppendLine();
                builder.AppendLine(issue.Summary);
                builder.AppendLine();
                builder.AppendLine($"> {issue.EvidenceExcerpt}");

                if (!string.IsNullOrWhiteSpace(issue.Note))
                {
                    builder.AppendLine();
                    builder.AppendLine($"Note: {issue.Note}");
                }

                builder.AppendLine();
            }
        }

        if (session.Screenshots.Count > 0)
        {
            builder.AppendLine("## Screenshots");
            builder.AppendLine();

            foreach (var screenshot in session.Screenshots)
            {
                builder.AppendLine(
                    $"- **{Path.GetFileName(screenshot.RelativePath)}** at `{SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)}` ({screenshot.Width}x{screenshot.Height})");
            }

            builder.AppendLine();
        }

        if (session.TimelineMoments.Count > 0)
        {
            builder.AppendLine("## Timeline Moments");
            builder.AppendLine();

            foreach (var moment in session.TimelineMoments.OrderBy(moment => moment.ElapsedSeconds))
            {
                builder.AppendLine($"- **{moment.Label}** at `{SessionTimeFormatter.FormatElapsedSeconds(moment.ElapsedSeconds)}`");
            }

            builder.AppendLine();
        }

        builder.AppendLine("## Transcript");
        builder.AppendLine();
        builder.AppendLine(string.IsNullOrWhiteSpace(session.TranscriptText)
            ? "_Transcript unavailable for this session._"
            : session.TranscriptText.Trim());

        return builder.ToString().TrimEnd() + Environment.NewLine;
    }

    private static string ToDisplayText(SessionTranscriptionStatus status)
    {
        return status switch
        {
            SessionTranscriptionStatus.Completed => "Completed",
            SessionTranscriptionStatus.NotConfigured => "OpenAI Key Not Configured",
            SessionTranscriptionStatus.Failed => "Failed",
            _ => status.ToString(),
        };
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
