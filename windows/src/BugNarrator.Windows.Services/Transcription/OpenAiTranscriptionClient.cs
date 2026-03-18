using System.Net.Http.Headers;
using System.Text.Json;
using BugNarrator.Windows.Services.Http;

namespace BugNarrator.Windows.Services.Transcription;

public sealed class OpenAiTranscriptionClient : ITranscriptionClient
{
    private static readonly Uri TranscriptionsEndpoint = new("https://api.openai.com/v1/audio/transcriptions");
    private static readonly Uri ModelsEndpoint = new("https://api.openai.com/v1/models");

    private readonly HttpClient httpClient;

    public OpenAiTranscriptionClient(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(5),
        };
    }

    public async Task<string> TranscribeToTextAsync(
        string audioFilePath,
        string apiKey,
        OpenAiTranscriptionRequest request,
        CancellationToken cancellationToken = default)
    {
        if (!File.Exists(audioFilePath))
        {
            throw new InvalidOperationException("The recorded audio file could not be found.");
        }

        var fileInfo = new FileInfo(audioFilePath);
        if (fileInfo.Length == 0)
        {
            throw new InvalidOperationException("The recorded audio file was empty.");
        }

        using var fileStream = File.OpenRead(audioFilePath);
        using var content = new MultipartFormDataContent();
        using var audioContent = new StreamContent(fileStream);

        audioContent.Headers.ContentType = new MediaTypeHeaderValue(GetMimeType(fileInfo.Extension));
        content.Add(audioContent, "file", fileInfo.Name);
        content.Add(new StringContent(request.Model), "model");
        content.Add(new StringContent("verbose_json"), "response_format");
        content.Add(new StringContent("0"), "temperature");

        if (!string.IsNullOrWhiteSpace(request.LanguageHint))
        {
            content.Add(new StringContent(request.LanguageHint), "language");
        }

        if (!string.IsNullOrWhiteSpace(request.Prompt))
        {
            content.Add(new StringContent(request.Prompt), "prompt");
        }

        using var message = new HttpRequestMessage(HttpMethod.Post, TranscriptionsEndpoint)
        {
            Content = content,
        };
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());

        using var response = await RemoteServiceRequestGuard.SendAsync(
            httpClient,
            message,
            "OpenAI transcription",
            cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(BuildFailureMessage(response.StatusCode, responseBody));
        }

        using var document = JsonDocument.Parse(responseBody);
        if (!document.RootElement.TryGetProperty("text", out var textElement))
        {
            throw new InvalidOperationException("OpenAI returned an invalid transcription response.");
        }

        var transcript = textElement.GetString()?.Trim();
        if (string.IsNullOrWhiteSpace(transcript))
        {
            throw new InvalidOperationException("OpenAI returned an empty transcript.");
        }

        return transcript;
    }

    public async Task ValidateApiKeyAsync(string apiKey, CancellationToken cancellationToken = default)
    {
        using var message = new HttpRequestMessage(HttpMethod.Get, ModelsEndpoint);
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());

        using var response = await RemoteServiceRequestGuard.SendAsync(
            httpClient,
            message,
            "OpenAI API validation",
            cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(BuildFailureMessage(response.StatusCode, responseBody));
        }
    }

    private static string BuildFailureMessage(System.Net.HttpStatusCode statusCode, string responseBody)
    {
        if (!string.IsNullOrWhiteSpace(responseBody))
        {
            try
            {
                using var document = JsonDocument.Parse(responseBody);
                if (document.RootElement.TryGetProperty("error", out var errorElement)
                    && errorElement.TryGetProperty("message", out var messageElement))
                {
                    var message = messageElement.GetString();
                    if (!string.IsNullOrWhiteSpace(message))
                    {
                        return message.Trim();
                    }
                }
            }
            catch
            {
                // Fall back to the HTTP status code if the body is not JSON.
            }
        }

        return statusCode switch
        {
            System.Net.HttpStatusCode.Unauthorized => "The OpenAI API key was rejected.",
            System.Net.HttpStatusCode.Forbidden => "The OpenAI API request was forbidden.",
            _ => $"OpenAI request failed with HTTP {(int)statusCode}.",
        };
    }

    private static string GetMimeType(string extension)
    {
        return extension.ToLowerInvariant() switch
        {
            ".wav" => "audio/wav",
            ".m4a" => "audio/m4a",
            ".mp3" => "audio/mpeg",
            _ => "application/octet-stream",
        };
    }
}
