using System.Globalization;
using System.Text;

namespace BugNarrator.Windows.Services.Http;

public static class ResponseBodyReader
{
    public const int SuccessBodyByteLimit = 16 * 1024 * 1024;
    public const int ErrorBodyByteLimit = 64 * 1024;
    public const int MessageCharacterLimit = 2048;

    public static async Task<string> ReadAsync(HttpResponseMessage response, CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(2));
        try
        {
            return response.IsSuccessStatusCode
                ? await ReadSuccessfulBodyAsync(response.Content, timeout.Token)
                : await ReadBoundedAsync(response.Content, timeout.Token);
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            throw new InvalidOperationException("The server response timed out. Check the connection and try again.", exception);
        }
    }

    private static async Task<string> ReadSuccessfulBodyAsync(HttpContent content, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (content.Headers.ContentLength is long declared && declared > SuccessBodyByteLimit)
        {
            throw new InvalidOperationException("The server reply exceeded BugNarrator's size limit.");
        }
        using var stream = await content.ReadAsStreamAsync(cancellationToken);
        using var payload = new MemoryStream();
        var buffer = new byte[8192];
        while (true)
        {
            // Read one byte beyond the ceiling at most, never a whole oversized body.
            var requested = (int)Math.Min(buffer.Length, SuccessBodyByteLimit - payload.Length + 1);
            var count = await stream.ReadAsync(buffer.AsMemory(0, requested), cancellationToken);
            if (count == 0) break;
            if (payload.Length + count > SuccessBodyByteLimit)
            {
                throw new InvalidOperationException("The server reply exceeded BugNarrator's size limit.");
            }
            payload.Write(buffer, 0, count);
        }
        // Preserve HttpContent's declared charset and BOM handling after bounding bytes.
        using var bounded = new ByteArrayContent(payload.ToArray());
        bounded.Headers.ContentType = content.Headers.ContentType;
        return await bounded.ReadAsStringAsync(cancellationToken);
    }

    public static async Task<string> ReadBoundedAsync(HttpContent content, CancellationToken cancellationToken = default)
    {
        using var stream = await content.ReadAsStreamAsync(cancellationToken);
        var buffer = new byte[ErrorBodyByteLimit];
        var length = 0;
        while (length < buffer.Length)
        {
            var count = await stream.ReadAsync(buffer.AsMemory(length), cancellationToken);
            if (count == 0) break;
            length += count;
        }
        // Partial or malformed JSON falls back to the callers' HTTP status message.
        return Encoding.UTF8.GetString(buffer, 0, length);
    }

    public static string SanitizeMessage(string message)
    {
        var bounded = message[..Math.Min(message.Length, MessageCharacterLimit)];
        if (bounded.Length > 0 && char.IsHighSurrogate(bounded[^1]))
            bounded = bounded[..^1];
        return new string(bounded.Select(c =>
            char.IsControl(c) || char.GetUnicodeCategory(c) is UnicodeCategory.Format
                or UnicodeCategory.LineSeparator or UnicodeCategory.ParagraphSeparator ? ' ' : c).ToArray());
    }
}
