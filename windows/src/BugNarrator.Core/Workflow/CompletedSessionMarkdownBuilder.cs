using System.Text;
using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

/// <summary>
/// Renders the session <c>transcript.md</c>. This follows the macOS
/// <c>TranscriptSession.markdownContent</c> contract, which the parity matrix declares must remain
/// identical across platforms. Review summary and extracted issues deliberately live in
/// <see cref="CompletedSessionReviewMarkdownBuilder"/> instead, mirroring the macOS split.
/// </summary>
public static class CompletedSessionMarkdownBuilder
{
    public static string Build(CompletedSession session)
    {
        return Build(session, SessionTimeFormatter.DefaultTimestampOptions);
    }

    public static string Build(CompletedSession session, SessionTimestampOptions timestampOptions)
    {
        var lines = new List<string>
        {
            "# BugNarrator Transcript",
            string.Empty,
            $"- Recorded: {SessionTimeFormatter.FormatTimestamp(session.CreatedAt, timestampOptions)}",
            $"- Duration: {SessionTimeFormatter.FormatDuration(session.Duration)}",
        };

        if (!string.IsNullOrWhiteSpace(session.TranscriptionModel))
        {
            lines.Add($"- Model: {session.TranscriptionModel}");
        }

        if (!string.IsNullOrWhiteSpace(session.LanguageHint))
        {
            lines.Add($"- Language Hint: {session.LanguageHint}");
        }

        if (!string.IsNullOrWhiteSpace(session.Prompt))
        {
            lines.Add($"- Prompt: {session.Prompt}");
        }

        // macOS only surfaces a status line for the pending-retry case. Windows has no retry state,
        // so the equivalent signal is a non-completed transcription status.
        if (session.TranscriptionStatus != SessionTranscriptionStatus.Completed)
        {
            lines.Add($"- Transcription Status: {ToDisplayText(session.TranscriptionStatus)}");

            if (!string.IsNullOrWhiteSpace(session.TranscriptionFailureMessage))
            {
                lines.Add($"- Transcription Note: {session.TranscriptionFailureMessage}");
            }
        }

        lines.Add(string.Empty);

        if (session.TimelineMoments.Count > 0)
        {
            lines.Add("## Markers");
            lines.Add(string.Empty);

            foreach (var moment in session.TimelineMoments.OrderBy(moment => moment.ElapsedSeconds))
            {
                var markerLine = $"- **{moment.Label}** at `{SessionTimeFormatter.FormatElapsedSeconds(moment.ElapsedSeconds)}`";
                if (!string.IsNullOrWhiteSpace(moment.Note))
                {
                    // macOS appends the marker note after an em dash.
                    markerLine += $" — {moment.Note}";
                }

                lines.Add(markerLine);
            }

            lines.Add(string.Empty);
        }

        if (session.Screenshots.Count > 0)
        {
            var timelineMomentsByScreenshotId = session.TimelineMoments
                .Where(moment => moment.RelatedScreenshotId.HasValue)
                .OrderBy(moment => moment.ElapsedSeconds)
                .GroupBy(moment => moment.RelatedScreenshotId!.Value)
                .ToDictionary(group => group.Key, group => group.First());

            lines.Add("## Screenshots");
            lines.Add(string.Empty);

            foreach (var screenshot in session.Screenshots)
            {
                var screenshotLine = $"- **{Path.GetFileName(screenshot.RelativePath)}** at `{SessionTimeFormatter.FormatElapsedSeconds(screenshot.ElapsedSeconds)}`";
                if (timelineMomentsByScreenshotId.TryGetValue(screenshot.ScreenshotId, out var moment))
                {
                    screenshotLine += $" linked to **{moment.Label}**";
                }

                lines.Add(screenshotLine);
            }

            lines.Add(string.Empty);
        }

        lines.Add("## Raw Transcript");
        lines.Add(string.Empty);
        lines.Add(string.IsNullOrWhiteSpace(session.TranscriptText)
            ? "Transcript not available yet."
            : session.TranscriptText.Trim());

        return SessionMarkdown.Join(lines);
    }

    private static string ToDisplayText(SessionTranscriptionStatus status)
    {
        return status switch
        {
            SessionTranscriptionStatus.Completed => "Completed",
            SessionTranscriptionStatus.NotConfigured => "AI Provider Not Configured",
            SessionTranscriptionStatus.Failed => "Failed",
            _ => status.ToString(),
        };
    }
}
