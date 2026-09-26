namespace BugNarrator.Core.Workflow;

public static class SessionTitleBuilder
{
    public static string Build(string fallbackTitle, string transcriptText)
    {
        if (string.IsNullOrWhiteSpace(transcriptText))
        {
            return fallbackTitle;
        }

        var trimmedTranscript = transcriptText.Trim();
        var sentenceBreak = trimmedTranscript.IndexOfAny(['.', '!', '?', '\r', '\n']);
        var title = sentenceBreak >= 0
            ? trimmedTranscript[..sentenceBreak]
            : trimmedTranscript;

        title = title.Trim();
        if (title.Length == 0)
        {
            return fallbackTitle;
        }

        return title.Length <= 80
            ? title
            : $"{title[..80].Trim()}...";
    }
}
