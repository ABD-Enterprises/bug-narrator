using System.Text.Json;
using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;

namespace BugNarrator.Windows.Services.Storage;

public sealed class FileSessionDraftStore : ISessionDraftStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    private readonly AppStoragePaths storagePaths;

    public FileSessionDraftStore(AppStoragePaths storagePaths)
    {
        this.storagePaths = storagePaths;
        Directory.CreateDirectory(storagePaths.SessionsDirectory);
    }

    public async Task<RecordingSessionDraft> CreateDraftAsync(DateTimeOffset startedAt, CancellationToken cancellationToken = default)
    {
        var sessionId = Guid.NewGuid();
        var timestamp = startedAt.ToUniversalTime().ToString("yyyyMMdd-HHmmss");
        var sessionDirectory = Path.Combine(storagePaths.SessionsDirectory, $"{timestamp}-{sessionId:N}");
        var metadataFilePath = Path.Combine(sessionDirectory, "session-draft.json");
        var audioFilePath = Path.Combine(sessionDirectory, "session.wav");

        Directory.CreateDirectory(sessionDirectory);

        var draft = new RecordingSessionDraft(
            sessionId,
            Title: $"Session {startedAt:yyyy-MM-dd HH:mm:ss}",
            CreatedAt: startedAt,
            RecordingStartedAt: startedAt,
            RecordingStoppedAt: null,
            SessionDirectory: sessionDirectory,
            AudioFilePath: audioFilePath,
            MetadataFilePath: metadataFilePath,
            Screenshots: Array.Empty<ScreenshotArtifact>(),
            TimelineMoments: Array.Empty<SessionTimelineMoment>(),
            State: RecordingWorkflowState.Idle,
            FailureMessage: null);

        await SaveAsync(draft, cancellationToken);
        return draft;
    }

    public async Task SaveAsync(RecordingSessionDraft draft, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(draft.SessionDirectory);

        var temporaryMetadataPath = $"{draft.MetadataFilePath}.tmp";
        var json = JsonSerializer.Serialize(draft, JsonOptions);

        await File.WriteAllTextAsync(temporaryMetadataPath, json, cancellationToken);
        File.Move(temporaryMetadataPath, draft.MetadataFilePath, overwrite: true);
    }
}
