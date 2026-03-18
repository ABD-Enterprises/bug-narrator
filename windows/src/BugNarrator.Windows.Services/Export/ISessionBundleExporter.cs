using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Export;

public interface ISessionBundleExporter
{
    Task<string> ExportAsync(
        CompletedSession session,
        CancellationToken cancellationToken = default);
}
