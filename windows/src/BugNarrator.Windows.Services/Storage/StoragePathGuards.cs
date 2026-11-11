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
        try
        {
            var root = Path.GetFullPath(rootDirectory);
            var candidate = Path.GetFullPath(candidatePath);
            var rootPrefix = EnsureTrailingSeparator(root);
            // The storage root is not one session or one artifact.
            if (string.Equals(Path.TrimEndingDirectorySeparator(root), Path.TrimEndingDirectorySeparator(candidate), StringComparison.OrdinalIgnoreCase)
                || !candidate.StartsWith(rootPrefix, StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }

            // A textual child can still traverse a junction or symbolic link. Reject
            // reparse points at the root and at every existing child component.
            var current = root;
            if (!IsOrdinaryPathComponent(current))
            {
                return false;
            }
            foreach (var component in candidate[rootPrefix.Length..].Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar))
            {
                current = Path.Combine(current, component);
                if (!IsOrdinaryPathComponent(current))
                {
                    return false;
                }
            }
            return true;
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException or IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static bool IsOrdinaryPathComponent(string path)
    {
        try
        {
            return (File.GetAttributes(path) & FileAttributes.ReparsePoint) == 0;
        }
        catch (FileNotFoundException)
        {
            // New session directories and files need not exist yet.
            return true;
        }
        catch (DirectoryNotFoundException)
        {
            return true;
        }
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
