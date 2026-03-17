using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Storage;

public interface ISessionDraftStore
{
    Task<RecordingSessionDraft> CreateDraftAsync(DateTimeOffset startedAt, CancellationToken cancellationToken = default);
    Task SaveAsync(RecordingSessionDraft draft, CancellationToken cancellationToken = default);
}
