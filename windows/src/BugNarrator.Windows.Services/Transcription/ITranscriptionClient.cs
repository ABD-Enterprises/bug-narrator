namespace BugNarrator.Windows.Services.Transcription;

public interface ITranscriptionClient
{
    Task<string> TranscribeToTextAsync(
        string audioFilePath,
        string apiKey,
        OpenAiTranscriptionRequest request,
        CancellationToken cancellationToken = default);

    Task ValidateApiKeyAsync(
        string apiKey,
        string? providerBaseUrl = null,
        CancellationToken cancellationToken = default);
}
