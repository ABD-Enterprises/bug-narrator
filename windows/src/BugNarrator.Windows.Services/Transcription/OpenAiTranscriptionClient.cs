using System.Net.Http.Headers;
using System.Text.Json;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Http;

namespace BugNarrator.Windows.Services.Transcription;

public sealed class OpenAiTranscriptionClient : ITranscriptionClient
{
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

        // The endpoint rejects uploads over 25 MB and a 16 kHz mono WAV crosses that at ~13
        // minutes. Cut an over-limit PCM WAV into ≤8-minute WAV chunks and join the texts, as
        // macOS joins its chunk transcripts (#1202). Anything else over the limit is refused
        // before the upload rather than after it.
        if (fileInfo.Length > WavUploadChunking.MaximumSingleUploadBytes)
        {
            return await TranscribeInChunksAsync(audioFilePath, fileInfo, apiKey, request, cancellationToken);
        }

        return await TranscribeSingleFileAsync(audioFilePath, fileInfo, apiKey, request, cancellationToken);
    }

    private async Task<string> TranscribeInChunksAsync(
        string audioFilePath,
        FileInfo fileInfo,
        string apiKey,
        OpenAiTranscriptionRequest request,
        CancellationToken cancellationToken)
    {
        if (!string.Equals(fileInfo.Extension, ".wav", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(OversizedMessage(fileInfo.Length));
        }

        using var source = File.OpenRead(audioFilePath);
        var layout = WavUploadChunking.ReadLayout(source);
        var spans = WavUploadChunking.Plan(layout.FrameCount, layout.SampleRate);
        if (spans.Count == 0)
        {
            // Within one chunk's duration yet over the byte limit: not the recorder's format.
            throw new InvalidOperationException(OversizedMessage(fileInfo.Length));
        }

        var chunkDirectory = Path.Combine(Path.GetTempPath(), "BugNarrator-Chunks-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(chunkDirectory);
        try
        {
            var parts = new List<string>(spans.Count);
            for (var index = 0; index < spans.Count; index++)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var chunkPath = Path.Combine(chunkDirectory, $"chunk-{index + 1:D3}.wav");
                using (var chunk = File.Create(chunkPath))
                {
                    WavUploadChunking.WriteChunk(source, layout, spans[index], chunk);
                }

                var text = await TranscribeSingleFileAsync(chunkPath, new FileInfo(chunkPath), apiKey, request, cancellationToken);
                parts.Add(text.Trim());
            }

            var transcript = string.Join("\n\n", parts.Where(part => part.Length > 0)).Trim();
            if (string.IsNullOrWhiteSpace(transcript))
            {
                throw new InvalidOperationException("The AI provider returned an empty transcript.");
            }

            return transcript;
        }
        finally
        {
            try { Directory.Delete(chunkDirectory, recursive: true); } catch { /* best effort */ }
        }
    }

    private static string OversizedMessage(long bytes) =>
        $"The recorded audio is {bytes / (1024.0 * 1024.0):0.#} MB, which is larger than BugNarrator's 24 MB safe upload limit. Shorten the recording or use a lower-bitrate source.";

    private async Task<string> TranscribeSingleFileAsync(
        string audioFilePath,
        FileInfo fileInfo,
        string apiKey,
        OpenAiTranscriptionRequest request,
        CancellationToken cancellationToken)
    {
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

        using var message = new HttpRequestMessage(
            HttpMethod.Post,
            OpenAiCompatibleEndpoint.Build(request.ProviderBaseUrl, "audio/transcriptions"))
        {
            Content = content,
        };
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        }

        using var response = await RemoteServiceRequestGuard.SendAsync(
            httpClient,
            message,
            "AI provider transcription",
            cancellationToken);
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException(BuildFailureMessage(response.StatusCode, responseBody));
        }

        using var document = JsonDocument.Parse(responseBody);
        if (!document.RootElement.TryGetProperty("text", out var textElement))
        {
            throw new InvalidOperationException("The AI provider returned an invalid transcription response.");
        }

        var transcript = textElement.GetString()?.Trim();
        if (string.IsNullOrWhiteSpace(transcript))
        {
            throw new InvalidOperationException("The AI provider returned an empty transcript.");
        }

        return transcript;
    }

    public async Task ValidateApiKeyAsync(
        string apiKey,
        string? providerBaseUrl = null,
        CancellationToken cancellationToken = default)
    {
        using var message = new HttpRequestMessage(
            HttpMethod.Get,
            OpenAiCompatibleEndpoint.Build(providerBaseUrl, "models"));
        if (!string.IsNullOrWhiteSpace(apiKey))
        {
            message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        }

        using var response = await RemoteServiceRequestGuard.SendAsync(
            httpClient,
            message,
            "AI provider validation",
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
            System.Net.HttpStatusCode.Unauthorized => "The AI provider credential was rejected.",
            System.Net.HttpStatusCode.Forbidden => "The AI provider request was forbidden.",
            _ => $"AI provider request failed with HTTP {(int)statusCode}.",
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
