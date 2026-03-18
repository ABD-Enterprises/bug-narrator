namespace BugNarrator.Windows.Services.Storage;

internal static class StoragePathGuards
{
    public static string EnsureDirectoryPathUnderRoot(
        string rootDirectory,
        string candidatePath,
        string subject)
    {
        return EnsurePathUnderRoot(rootDirectory, candidatePath, subject);
    }

    public static string EnsureFilePathUnderRoot(
        string rootDirectory,
        string candidatePath,
        string subject)
    {
        return EnsurePathUnderRoot(rootDirectory, candidatePath, subject);
    }

    public static bool TryResolveRelativePathUnderRoot(
        string rootDirectory,
        string relativePath,
        out string absolutePath)
    {
        absolutePath = string.Empty;
        if (string.IsNullOrWhiteSpace(relativePath))
        {
            return false;
        }

        var normalizedRelativePath = relativePath
            .Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar)
            .TrimStart(Path.DirectorySeparatorChar);

        if (Path.IsPathRooted(normalizedRelativePath))
        {
            return false;
        }

        var combinedPath = Path.Combine(rootDirectory, normalizedRelativePath);
        var normalizedCombinedPath = Path.GetFullPath(combinedPath);
        if (!IsPathUnderRoot(rootDirectory, normalizedCombinedPath))
        {
            return false;
        }

        absolutePath = normalizedCombinedPath;
        return true;
    }

    public static bool IsPathUnderRoot(string rootDirectory, string candidatePath)
    {
        var normalizedRootDirectory = EnsureTrailingSeparator(Path.GetFullPath(rootDirectory));
        var normalizedCandidatePath = EnsureTrailingSeparator(Path.GetFullPath(candidatePath));

        return normalizedCandidatePath.StartsWith(
            normalizedRootDirectory,
            StringComparison.OrdinalIgnoreCase);
    }

    private static string EnsurePathUnderRoot(
        string rootDirectory,
        string candidatePath,
        string subject)
    {
        if (string.IsNullOrWhiteSpace(candidatePath))
        {
            throw new InvalidOperationException($"The {subject} path was empty.");
        }

        var normalizedCandidatePath = Path.GetFullPath(candidatePath);
        if (!IsPathUnderRoot(rootDirectory, normalizedCandidatePath))
        {
            throw new InvalidOperationException(
                $"Refusing to use a {subject} path outside the expected BugNarrator storage root: {candidatePath}");
        }

        return normalizedCandidatePath;
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return path.EndsWith(Path.DirectorySeparatorChar)
            ? path
            : $"{path}{Path.DirectorySeparatorChar}";
    }
}
