using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Storage;

public sealed class FileCompletedSessionStore : ICompletedSessionStore
{
    private const long MaxMetadataBytes = 4 * 1024 * 1024;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string sessionsDirectory;

    public FileCompletedSessionStore(AppStoragePaths storagePaths)
    {
        sessionsDirectory = storagePaths.SessionsDirectory;
        Directory.CreateDirectory(sessionsDirectory);
    }

    public async Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(sessionsDirectory))
        {
            return Array.Empty<CompletedSession>();
        }

        var sessions = new List<CompletedSession>();
        foreach (var sessionDirectory in Directory.EnumerateDirectories(sessionsDirectory))
        {
            cancellationToken.ThrowIfCancellationRequested();

            var metadataPath = Path.Combine(sessionDirectory, "session.json");
            if (!File.Exists(metadataPath))
            {
                continue;
            }

            try
            {
                var fileInfo = new FileInfo(metadataPath);
                if (fileInfo.Length > MaxMetadataBytes)
                {
                    continue;
                }

                var json = await File.ReadAllTextAsync(metadataPath, cancellationToken);
                var session = JsonSerializer.Deserialize<CompletedSession>(json, JsonOptions);
                if (session is not null)
                {
                    sessions.Add(SessionArtifactPathPolicy.NormalizeCompletedSession(session, sessionsDirectory));
                }
            }
            catch
            {
                // Skip corrupt or partial session metadata so the library stays usable.
            }
        }

        return sessions
            .OrderByDescending(session => session.CreatedAt)
            .ThenByDescending(session => session.SessionId)
            .ToArray();
    }

    public async Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default)
    {
        var normalizedSession = SessionArtifactPathPolicy.NormalizeCompletedSession(session, sessionsDirectory);
        Directory.CreateDirectory(normalizedSession.SessionDirectory);

        var json = JsonSerializer.Serialize(normalizedSession, JsonOptions);
        await AtomicFileOperations.WriteAllTextAsync(normalizedSession.MetadataFilePath, json, cancellationToken);

        var markdown = CompletedSessionMarkdownBuilder.Build(normalizedSession);
        await AtomicFileOperations.WriteAllTextAsync(
            normalizedSession.TranscriptMarkdownFilePath,
            markdown,
            cancellationToken);
    }

    public Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var sessionDirectory = ResolveSessionDirectory(session);
        if (sessionDirectory is null || !Directory.Exists(sessionDirectory))
        {
            return Task.CompletedTask;
        }

        EnsurePathIsUnderSessionsRoot(sessionDirectory);
        Directory.Delete(sessionDirectory, recursive: true);
        return Task.CompletedTask;
    }

    private string? ResolveSessionDirectory(CompletedSession session)
    {
        var candidatePaths = new[]
        {
            session.SessionDirectory,
            Path.GetDirectoryName(session.MetadataFilePath),
            Path.GetDirectoryName(session.TranscriptMarkdownFilePath),
        };

        foreach (var candidatePath in candidatePaths)
        {
            if (!string.IsNullOrWhiteSpace(candidatePath))
            {
                return Path.GetFullPath(candidatePath);
            }
        }

        return null;
    }

    private void EnsurePathIsUnderSessionsRoot(string sessionDirectory)
    {
        var normalizedRoot = EnsureTrailingSeparator(Path.GetFullPath(sessionsDirectory));
        var normalizedSessionDirectory = EnsureTrailingSeparator(Path.GetFullPath(sessionDirectory));

        if (!normalizedSessionDirectory.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException(
                $"Refusing to delete session content outside the BugNarrator Sessions directory: {sessionDirectory}");
        }
    }

    private static string EnsureTrailingSeparator(string path)
    {
        return path.EndsWith(Path.DirectorySeparatorChar)
            ? path
            : $"{path}{Path.DirectorySeparatorChar}";
    }
}
