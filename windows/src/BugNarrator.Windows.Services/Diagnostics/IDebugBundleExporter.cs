using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Diagnostics;

public interface IDebugBundleExporter
{
    Task<string> ExportAsync(
        CompletedSession? session,
        CancellationToken cancellationToken = default);
}
