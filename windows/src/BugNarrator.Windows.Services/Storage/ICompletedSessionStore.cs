using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Storage;

public interface ICompletedSessionStore
{
    /// <summary>Root under which sessions live; SampleSession.Make roots the bundled demo here.</summary>
    string SessionsDirectory { get; }

    Task<IReadOnlyList<CompletedSession>> GetAllAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(CompletedSession session, CancellationToken cancellationToken = default);
    Task DeleteAsync(CompletedSession session, CancellationToken cancellationToken = default);
}
