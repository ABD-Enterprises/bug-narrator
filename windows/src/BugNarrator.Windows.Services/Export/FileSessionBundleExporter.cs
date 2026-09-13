using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using BugNarrator.Windows.Services.Diagnostics;
using BugNarrator.Windows.Services.Storage;

namespace BugNarrator.Windows.Services.Export;

public sealed class FileSessionBundleExporter : ISessionBundleExporter
{
    // contract-fixtures/session-bundle-layout.json lists manifest.json as always present. The key set
    // and exportedFiles order mirror the macOS SessionBundleManifest (TranscriptExporter.swift) so a
    // bundle from either platform reads the same. Properties are declared alphabetically because macOS
    // writes with .sortedKeys and System.Text.Json emits in declaration order.
    private static readonly JsonSerializerOptions ManifestJsonOptions = new()
    {
        WriteIndented = true,
    };

    private static readonly UTF8Encoding ManifestEncoding = new(encoderShouldEmitUTF8Identifier: false);

    private sealed record SessionBundleManifest(
        [property: JsonPropertyName("copiedScreenshotCount")] int CopiedScreenshotCount,
        [property: JsonPropertyName("exportedFiles")] IReadOnlyList<string> ExportedFiles,
        [property: JsonPropertyName("generatedAt")] DateTimeOffset GeneratedAt,
        [property: JsonPropertyName("missingScreenshots")] IReadOnlyList<string> MissingScreenshots,
        [property: JsonPropertyName("notes")] IReadOnlyList<string> Notes,
        [property: JsonPropertyName("screenshotCount")] int ScreenshotCount,
        [property: JsonPropertyName("sessionID")] string SessionId);

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
        var exportedFiles = new List<string> { "transcript.md" };

        if (CompletedSessionReviewMarkdownBuilder.HasReviewOutput(normalizedSession))
        {
            var summaryPath = Path.Combine(bundleDirectory, "summary.md");
            var summaryMarkdown = CompletedSessionReviewMarkdownBuilder.Build(normalizedSession);
            await AtomicFileOperations.WriteAllTextAsync(summaryPath, summaryMarkdown, cancellationToken);
            exportedFiles.Add("summary.md");
        }

        var screenshotsDirectory = Path.Combine(bundleDirectory, "screenshots");
        Directory.CreateDirectory(screenshotsDirectory);

        var copiedScreenshots = 0;
        var missingScreenshots = new List<string>();

        foreach (var screenshot in normalizedSession.Screenshots.OrderBy(screenshot => screenshot.ElapsedSeconds))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var fileName = Path.GetFileName(screenshot.RelativePath);
            if (!File.Exists(screenshot.AbsolutePath))
            {
                missingScreenshots.Add(fileName);
                continue;
            }

            var destinationPath = GetUniqueDestinationPath(Path.Combine(screenshotsDirectory, fileName));
            File.Copy(screenshot.AbsolutePath, destinationPath, overwrite: false);
            copiedScreenshots++;
            exportedFiles.Add($"screenshots/{Path.GetFileName(destinationPath)}");
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
                // Windows-only directory, outside the shared layout contract but still a file this
                // bundle wrote, so the manifest lists it. Kept before manifest.json so that stays last.
                exportedFiles.Add($"annotated-exports/{Path.GetFileName(destinationPath)}");
            }
        }

        exportedFiles.Add("manifest.json");
        var manifest = new SessionBundleManifest(
            CopiedScreenshotCount: copiedScreenshots,
            ExportedFiles: exportedFiles,
            GeneratedAt: DateTimeOffset.UtcNow,
            MissingScreenshots: missingScreenshots,
            Notes: ManifestNotes(missingScreenshots.Count),
            ScreenshotCount: normalizedSession.Screenshots.Count,
            SessionId: normalizedSession.SessionId.ToString().ToUpperInvariant());
        // Bytes, not text: WriteAllTextAsync goes through Encoding.UTF8, whose BOM makes the file
        // invalid JSON (RFC 8259 §8.1) and unreadable by JsonDocument.Parse. macOS writes no BOM.
        await AtomicFileOperations.WriteAllBytesAsync(
            Path.Combine(bundleDirectory, "manifest.json"),
            ManifestEncoding.GetBytes(JsonSerializer.Serialize(manifest, ManifestJsonOptions)),
            cancellationToken);

        diagnostics.Info(
            "export",
            $"session bundle exported to {bundleDirectory} (copied {copiedScreenshots} screenshot(s), missing {missingScreenshots.Count})");

        return bundleDirectory;
    }

    // Same two sentences macOS writes (TranscriptExporter.manifestNotes), so a reader of either
    // platform's manifest gets the same explanation.
    private static IReadOnlyList<string> ManifestNotes(int missingScreenshotCount)
    {
        var notes = new List<string>
        {
            "This bundle contains the transcript, review output, and captured screenshots for one BugNarrator session.",
        };

        if (missingScreenshotCount > 0)
        {
            notes.Add(
                $"{missingScreenshotCount} referenced screenshot file(s) were not found on disk at export time and are listed in missingScreenshots. The rest of the bundle exported normally.");
        }

        return notes;
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
