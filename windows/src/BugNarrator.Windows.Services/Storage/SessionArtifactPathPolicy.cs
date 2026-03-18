using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Storage;

internal static class SessionArtifactPathPolicy
{
    public static CompletedSession NormalizeCompletedSession(
        CompletedSession session,
        string sessionsRootDirectory)
    {
        var sessionDirectory = StoragePathGuards.EnsureDirectoryPathUnderRoot(
            sessionsRootDirectory,
            session.SessionDirectory,
            "completed session directory");

        return session with
        {
            SessionDirectory = sessionDirectory,
            AudioFilePath = NormalizeKnownFilePath(session.AudioFilePath, sessionDirectory, "session.wav"),
            MetadataFilePath = NormalizeKnownFilePath(session.MetadataFilePath, sessionDirectory, "session.json"),
            TranscriptMarkdownFilePath = NormalizeKnownFilePath(session.TranscriptMarkdownFilePath, sessionDirectory, "transcript.md"),
            Screenshots = session.Screenshots
                .Select(screenshot => TryNormalizeScreenshot(sessionDirectory, screenshot, out var normalizedScreenshot)
                    ? normalizedScreenshot
                    : null)
                .OfType<ScreenshotArtifact>()
                .ToArray(),
        };
    }

    public static bool TryNormalizeScreenshot(
        string sessionDirectory,
        ScreenshotArtifact screenshot,
        out ScreenshotArtifact normalizedScreenshot)
    {
        normalizedScreenshot = default!;

        var normalizedRelativePath = NormalizeRelativePath(screenshot.RelativePath);
        if (!StoragePathGuards.TryResolveRelativePathUnderRoot(
                sessionDirectory,
                normalizedRelativePath,
                out var normalizedAbsolutePath))
        {
            return false;
        }

        normalizedScreenshot = screenshot with
        {
            RelativePath = normalizedRelativePath,
            AbsolutePath = normalizedAbsolutePath,
        };

        return true;
    }

    private static string NormalizeKnownFilePath(
        string candidatePath,
        string sessionDirectory,
        string defaultFileName)
    {
        if (!string.IsNullOrWhiteSpace(candidatePath))
        {
            try
            {
                return StoragePathGuards.EnsureFilePathUnderRoot(
                    sessionDirectory,
                    candidatePath,
                    "session artifact");
            }
            catch
            {
                // Fall back to the deterministic session-local file name below.
            }
        }

        return Path.Combine(sessionDirectory, defaultFileName);
    }

    private static string NormalizeRelativePath(string relativePath)
    {
        return relativePath
            .Replace(Path.DirectorySeparatorChar, '/')
            .Replace(Path.AltDirectorySeparatorChar, '/')
            .TrimStart('/');
    }
}
