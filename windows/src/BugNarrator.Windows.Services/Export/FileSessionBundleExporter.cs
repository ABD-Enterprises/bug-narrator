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

        // Always regenerate rather than copying the session's stored transcript.md: a file written by
        // an earlier build still carries the pre-parity contract, so copying it would silently export
        // the old shape.
        var transcriptPath = Path.Combine(bundleDirectory, "transcript.md");
        var markdown = CompletedSessionMarkdownBuilder.Build(normalizedSession);
        await AtomicFileOperations.WriteAllTextAsync(transcriptPath, markdown, cancellationToken);

        if (CompletedSessionReviewMarkdownBuilder.HasReviewOutput(normalizedSession))
        {
            var summaryPath = Path.Combine(bundleDirectory, "summary.md");
            var summaryMarkdown = CompletedSessionReviewMarkdownBuilder.Build(normalizedSession);
            await AtomicFileOperations.WriteAllTextAsync(summaryPath, summaryMarkdown, cancellationToken);
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

        var annotatedExportsDirectory = Path.Combine(normalizedSession.SessionDirectory, "annotated-exports");
        if (Directory.Exists(annotatedExportsDirectory))
        {
            var bundleAnnotatedExportsDirectory = Path.Combine(bundleDirectory, "annotated-exports");
            Directory.CreateDirectory(bundleAnnotatedExportsDirectory);

            foreach (var filePath in Directory.EnumerateFiles(annotatedExportsDirectory, "*.png").OrderBy(Path.GetFileName))
            {
                cancellationToken.ThrowIfCancellationRequested();

                var destinationPath = GetUniqueDestinationPath(
                    Path.Combine(bundleAnnotatedExportsDirectory, Path.GetFileName(filePath)));
                File.Copy(filePath, destinationPath, overwrite: false);
            }
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
            builder.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

        return string.IsNullOrWhiteSpace(builder)
            ? "session"
            : builder.Length <= 48
                ? builder
                : builder[..48].Trim('-');
    }
}
