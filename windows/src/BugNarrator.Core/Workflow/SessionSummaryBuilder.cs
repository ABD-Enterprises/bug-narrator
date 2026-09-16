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
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)} with {screenshotCount} screenshot artifacts. Finish AI provider setup in Settings to transcribe future sessions.",
            SessionTranscriptionStatus.Failed =>
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)}, but transcription failed. {transcriptionFailureMessage ?? "Review the saved audio and logs for details."}",
            _ =>
                $"Recording saved locally for {SessionTimeFormatter.FormatDuration(duration)} with {screenshotCount} screenshot artifacts.",
        };
    }

    private static string ExtractLeadSentence(string transcriptText)
    {
        var sentenceBreak = FirstSentenceBreak(transcriptText);
        if (sentenceBreak >= 0 && sentenceBreak < 220)
        {
            return transcriptText[..(sentenceBreak + 1)].Trim();
        }

        return transcriptText.Length <= 220
            ? transcriptText
            : $"{transcriptText[..220].Trim()}...";
    }

    /// <summary>
    /// The index of the '.', '!' or '?' that ends the first sentence: one followed by whitespace or
    /// the end of the text. A terminator followed by anything else is inside a token — "1.2",
    /// "Mr.", "Wait...what" — and used to end the summary at "Version 1." (#1194).
    /// </summary>
    private static int FirstSentenceBreak(string text)
    {
        for (var index = text.IndexOfAny(SentenceTerminators); index >= 0; index = text.IndexOfAny(SentenceTerminators, index + 1))
        {
            if (index + 1 == text.Length || char.IsWhiteSpace(text[index + 1]))
            {
                return index;
            }
        }

        return -1;
    }

    private static readonly char[] SentenceTerminators = ['.', '!', '?'];
}
