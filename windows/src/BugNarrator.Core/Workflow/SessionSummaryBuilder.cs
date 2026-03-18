using BugNarrator.Core.Models;

namespace BugNarrator.Core.Workflow;

public static class SessionSummaryBuilder
{
    public static string Build(
        string transcriptText,
        SessionTranscriptionStatus transcriptionStatus,
        string? transcriptionFailureMessage,
        int screenshotCount,
        TimeSpan duration)
    {
        if (!string.IsNullOrWhiteSpace(transcriptText))
        {
            var normalized = transcriptText.Trim();
            var sentence = ExtractLeadSentence(normalized);
            var screenshotPhrase = screenshotCount == 1
                ? "1 screenshot"
                : $"{screenshotCount} screenshots";

            return $"{sentence} Session length {SessionTimeFormatter.FormatDuration(duration)} with {screenshotPhrase}.";
        }

        return transcriptionStatus switch
        {
            SessionTranscriptionStatus.NotConfigured =>
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)} with {screenshotCount} screenshot artifacts. Add an OpenAI API key in Settings to transcribe future sessions.",
            SessionTranscriptionStatus.Failed =>
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)}, but transcription failed. {transcriptionFailureMessage ?? "Review the saved audio and logs for details."}",
            _ =>
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)} with {screenshotCount} screenshot artifacts.",
        };
    }

    private static string ExtractLeadSentence(string transcriptText)
    {
        var sentenceBreak = transcriptText.IndexOfAny(['.', '!', '?']);
        if (sentenceBreak >= 0 && sentenceBreak < 220)
        {
            return transcriptText[..(sentenceBreak + 1)].Trim();
        }

        return transcriptText.Length <= 220
            ? transcriptText
            : $"{transcriptText[..220].Trim()}...";
    }
}
