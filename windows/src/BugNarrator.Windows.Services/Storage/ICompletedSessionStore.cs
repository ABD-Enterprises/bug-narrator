using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Storage;

public interface ICompletedSessionStore
{
    Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default);
    Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default);
}
