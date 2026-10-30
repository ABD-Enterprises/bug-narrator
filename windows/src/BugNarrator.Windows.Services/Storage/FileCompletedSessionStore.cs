using System.Text;
using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Storage;

public sealed class FileCompletedSessionStore : ICompletedSessionStore
{
    private const long MaxMetadataBytes = 4 * 1024 * 1024;
    private const long MaxStoredMetadataBytes = MaxMetadataBytes + WindowsSessionDataProtector.MaxEnvelopeOverhead;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly string sessionsDirectory;
    private readonly ISessionDataProtector dataProtector;

    public string SessionsDirectory => sessionsDirectory;

    public FileCompletedSessionStore(AppStoragePaths storagePaths, ISessionDataProtector? dataProtector = null)
    {
        this.dataProtector = dataProtector ?? new WindowsSessionDataProtector();
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
                if (fileInfo.Length > MaxStoredMetadataBytes)
                {
                    continue;
                }

                var payload = await File.ReadAllBytesAsync(metadataPath, cancellationToken);
                var plaintext = dataProtector.Unprotect(payload);
                if (plaintext.Length > MaxMetadataBytes)
                {
                    continue;
                }

                var json = Encoding.UTF8.GetString(plaintext).TrimStart('\uFEFF');
                var session = JsonSerializer.Deserialize<CompletedSession>(json, JsonOptions);
                if (session is not null)
                {
                    sessions.Add(SessionArtifactPathPolicy.NormalizeCompletedSession(session, sessionsDirectory));
                }
            }
            catch (OperationCanceledException)
            {
                throw;
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

        var metadata = Encoding.UTF8.GetBytes(JsonSerializer.Serialize(normalizedSession, JsonOptions));
        if (metadata.Length > MaxMetadataBytes)
        {
            throw new InvalidDataException("The session metadata is too large to save.");
        }

        var artifacts = new List<(string Path, byte[] Payload)>
        {
            (normalizedSession.MetadataFilePath, dataProtector.Protect(metadata)),
            (normalizedSession.TranscriptMarkdownFilePath, ProtectText(CompletedSessionMarkdownBuilder.Build(normalizedSession))),
        };
        var summaryPath = Path.Combine(normalizedSession.SessionDirectory, "summary.md");
        if (CompletedSessionReviewMarkdownBuilder.HasReviewOutput(normalizedSession))
        {
            artifacts.Add((summaryPath, ProtectText(CompletedSessionReviewMarkdownBuilder.Build(normalizedSession))));
        }

        var draftPath = Path.Combine(normalizedSession.SessionDirectory, "session-draft.json");
        if (File.Exists(draftPath))
        {
            if (new FileInfo(draftPath).Length > MaxStoredMetadataBytes)
            {
                throw new InvalidDataException("The saved recording draft is too large to protect.");
            }

            var draft = dataProtector.Unprotect(await File.ReadAllBytesAsync(draftPath, cancellationToken));
            if (draft.Length > MaxMetadataBytes)
            {
                throw new InvalidDataException("The saved recording draft is too large to protect.");
            }

            artifacts.Add((draftPath, dataProtector.Protect(draft)));
        }

        // Prepare every envelope before replacing any file; encryption failures never write plaintext.
        foreach (var (path, payload) in artifacts)
        {
            cancellationToken.ThrowIfCancellationRequested();
            await AtomicFileOperations.WriteAllBytesAsync(path, payload, cancellationToken);
        }

        if (!CompletedSessionReviewMarkdownBuilder.HasReviewOutput(normalizedSession))
        {
            File.Delete(summaryPath);
        }
    }

    private byte[] ProtectText(string text) => dataProtector.Protect(Encoding.UTF8.GetBytes(text));

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
