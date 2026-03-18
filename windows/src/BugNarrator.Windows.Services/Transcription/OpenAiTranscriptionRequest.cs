namespace BugNarrator.Windows.Services.Transcription;

public sealed record OpenAiTranscriptionRequest(
    string Model,
    string? LanguageHint,
    string? Prompt
);
