using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Export;

public sealed class FileSessionBundleExporter : ISessionBundleExporter
{
    private readonly WindowsDiagnostics diagnostics;
    private readonly string exportRootDirectory;
    private readonly string sessionsRootDirectory;

    public FileSessionBundleExporter(
        AppStoragePaths storagePaths,
        WindowsDiagnostics diagnostics)
    {
        exportRootDirectory = storagePaths.SessionBundlesDirectory;
        sessionsRootDirectory = storagePaths.SessionsDirectory;
        Directory.CreateDirectory(exportRootDirectory);
        this.diagnostics = diagnostics;
    }

    public async Task<string> ExportAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default)
    {
        var normalizedSession = SessionArtifactPathPolicy.NormalizeCompletedSession(session, sessionsRootDirectory);
        var bundleDirectory = CreateUniqueBundleDirectory(session);
        Directory.CreateDirectory(bundleDirectory);

        var transcriptPath = Path.Combine(bundleDirectory, "transcript.md");
        if (File.Exists(normalizedSession.TranscriptMarkdownFilePath))
        {
            File.Copy(normalizedSession.TranscriptMarkdownFilePath, transcriptPath, overwrite: true);
        }
        else
        {
            var markdown = CompletedSessionMarkdownBuilder.Build(normalizedSession);
            await AtomicFileOperations.WriteAllTextAsync(transcriptPath, markdown, cancellationToken);
        }

        var screenshotsDirectory = Path.Combine(bundleDirectory, "screenshots");
        Directory.CreateDirectory(screenshotsDirectory);

        var copiedScreenshots = 0;
        var missingScreenshots = 0;

        foreach (var screenshot in normalizedSession.Screenshots.OrderBy(screenshot => screenshot.ElapsedSeconds))
        {
            cancellationToken.ThrowIfCancellationRequested();

            if (!File.Exists(screenshot.AbsolutePath))
            {
                missingScreenshots++;
                continue;
            }

            var destinationPath = GetUniqueDestinationPath(
                Path.Combine(screenshotsDirectory, Path.GetFileName(screenshot.RelativePath)));
            File.Copy(screenshot.AbsolutePath, destinationPath, overwrite: false);
            copiedScreenshots++;
        }

        diagnostics.Info(
            "export",
            $"session bundle exported to {bundleDirectory} (copied {copiedScreenshots} screenshot(s), missing {missingScreenshots})");

        return bundleDirectory;
    }

    private string CreateUniqueBundleDirectory(CompletedSession session)
    {
        var timestamp = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd-HHmmss");
        var slug = SanitizeForPath(session.Title);
        var directoryName = $"bugnarrator-session-{timestamp}-{slug}";
        var candidatePath = Path.Combine(exportRootDirectory, directoryName);
        var suffix = 2;

        while (Directory.Exists(candidatePath))
        {
            candidatePath = Path.Combine(exportRootDirectory, $"{directoryName}-{suffix}");
            suffix++;
        }

        return candidatePath;
    }

    private static string GetUniqueDestinationPath(string path)
    {
        if (!File.Exists(path))
        {
            return path;
        }

        var directory = Path.GetDirectoryName(path)!;
        var fileNameWithoutExtension = Path.GetFileNameWithoutExtension(path);
        var extension = Path.GetExtension(path);
        var suffix = 2;

        while (true)
        {
            var candidatePath = Path.Combine(directory, $"{fileNameWithoutExtension}-{suffix}{extension}");
            if (!File.Exists(candidatePath))
            {
                return candidatePath;
            }

            suffix++;
        }
    }

    private static string SanitizeForPath(string value)
    {
        var invalidCharacters = Path.GetInvalidFileNameChars();
        var builder = new string(
            value.Trim()
                .Select(character => invalidCharacters.Contains(character) ? '-' : character)
                .ToArray());

        builder = string.Join(
            "-",
            builder.Split([' ', '\t'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

        return string.IsNullOrWhiteSpace(builder)
            ? "session"
            : builder.Length <= 48
                ? builder
                : builder[..48].Trim('-');
    }
}
