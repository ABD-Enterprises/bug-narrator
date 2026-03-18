using BugNarrator.Core.Models;

namespace BugNarrator.Windows.Services.Extraction;

public interface IIssueExtractionService
{
    Task<IssueExtractionResult> ExtractAsync(
        CompletedSession session,
        string apiKey,
        string model,
        CancellationToken cancellationToken = default);
}
