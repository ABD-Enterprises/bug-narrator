using System.Text;

namespace BugNarrator.Windows.Services.Http;

/// <summary>
/// Reads the body of a failed response with a bound on how much of it is kept,
/// and turns it into a message that is safe to write to the log.
/// </summary>
/// <remarks>
/// A server answers with as much as it likes. The body of a failed request is
/// interpolated into an error message that ends up in the log file, so an
/// unbounded read is a disk-fill vector, and a body that carries newlines is
/// a log-injection vector: the log would carry lines that look like they
/// came from somewhere else.
/// </remarks>
public static class ResponseBodyReader
{
    /// <summary>The most bytes of a failed response that are read.</summary>
    public const int MaxErrorBodyBytes = 64 * 1024;

    /// <summary>The most characters of a failed response that reach the log.</summary>
    public const int MaxLoggedMessageCharacters = 2 * 1024;

    /// <summary>
    /// Reads at most <see cref="MaxErrorBodyBytes"/> bytes of the response
    /// body. The body is cut rather than refused: a truncated body still tells
    /// the user what the server said, and it cannot fill the disk.
    /// </summary>
    public static async Task<string> ReadErrorBodyAsync(
        HttpResponseMessage response,
        CancellationToken cancellationToken = default)
    {
        using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var buffer = new byte[MaxErrorBodyBytes];
        var read = 0;

        while (read < buffer.Length)
        {
            var chunk = await stream.ReadAsync(
                buffer.AsMemory(read, buffer.Length - read),
                cancellationToken);
            if (chunk == 0)
            {
                break;
            }

            read += chunk;
        }

        return Encoding.UTF8.GetString(buffer, 0, read);
    }

    /// <summary>
    /// Makes a message taken from a failed response safe to write to the log:
    /// it is cut to a length that cannot fill the disk, and control characters
    /// are replaced so the body cannot forge a log line.
    /// </summary>
    public static string ToLoggableMessage(string? message)
    {
        if (string.IsNullOrWhiteSpace(message))
        {
            return string.Empty;
        }

        var builder = new StringBuilder(Math.Min(message.Length, MaxLoggedMessageCharacters));
        foreach (var character in message)
        {
            if (builder.Length >= MaxLoggedMessageCharacters)
            {
                builder.Append(" [truncated]");
                break;
            }

            builder.Append(char.IsControl(character) ? ' ' : character);
        }

        return builder.ToString().Trim();
    }
}
