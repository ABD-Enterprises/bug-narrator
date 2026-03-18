using System.Text;

namespace BugNarrator.Windows.Services.Storage;

internal static class AtomicFileOperations
{
    public static Task WriteAllTextAsync(
        string destinationPath,
        string content,
        CancellationToken cancellationToken = default)
    {
        return WriteAsync(
            destinationPath,
            temporaryPath => File.WriteAllTextAsync(temporaryPath, content, Encoding.UTF8, cancellationToken));
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
