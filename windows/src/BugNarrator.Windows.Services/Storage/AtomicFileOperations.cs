using System.Text;

namespace BugNarrator.Windows.Services.Storage;

internal static class AtomicFileOperations
{
    // Encoding.UTF8 (the static instance) emits a byte-order mark, so every text artifact this helper
    // wrote — transcript.md, summary.md, session.json, the debug bundle — began with EF BB BF. macOS
    // writes none of its counterparts with a BOM, the shared fixtures have none, and RFC 8259 §8.1
    // forbids one in JSON. Readers that use File.ReadAllText never noticed because it strips the BOM;
    // byte-level readers (JsonDocument.Parse on bytes, the fixture comparison) did.
    private static readonly UTF8Encoding Utf8WithoutBom = new(encoderShouldEmitUTF8Identifier: false);

    public static Task WriteAllTextAsync(
        string destinationPath,
        string content,
        CancellationToken cancellationToken = default)
    {
        return WriteAsync(
            destinationPath,
            temporaryPath => File.WriteAllTextAsync(temporaryPath, content, Utf8WithoutBom, cancellationToken));
    }

    public static Task WriteAllBytesAsync(
        string destinationPath,
        byte[] content,
        CancellationToken cancellationToken = default)
    {
        return WriteAsync(
            destinationPath,
            temporaryPath => File.WriteAllBytesAsync(temporaryPath, content, cancellationToken));
    }

    private static async Task WriteAsync(
        string destinationPath,
        Func<string, Task> writeTemporaryFileAsync)
    {
        var directoryPath = Path.GetDirectoryName(destinationPath)
                            ?? throw new InvalidOperationException($"Unable to resolve the directory for {destinationPath}.");
        Directory.CreateDirectory(directoryPath);

        var temporaryPath = Path.Combine(
            directoryPath,
            $".{Path.GetFileName(destinationPath)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await writeTemporaryFileAsync(temporaryPath);
            File.Move(temporaryPath, destinationPath, overwrite: true);
        }
        catch
        {
            TryDelete(temporaryPath);
            throw;
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Cleanup failures should never mask the original error.
        }
    }
}
