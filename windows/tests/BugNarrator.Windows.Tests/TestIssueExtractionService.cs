using BugNarrator.Core.Models;
using BugNarrator.Windows.Services.Extraction;

namespace BugNarrator.Windows.Tests;

/// <summary>Shared fake for the lifecycle harnesses: records calls, returns a canned result, or throws.</summary>
internal sealed class TestIssueExtractionService : IIssueExtractionService
{
    public int CallCount { get; private set; }
    public CompletedSession? LastSession { get; private set; }
    public Exception? ExceptionToThrow { get; set; }
    public IssueExtractionResult Result { get; set; } = ReviewSessionTestData.CreateIssueExtractionResult();

    public Task<IssueExtractionResult> ExtractAsync(
        CompletedSession session,
        string apiKey,
        string model,
        string? providerBaseUrl,
        CancellationToken cancellationToken = default)
    {
        CallCount++;
        LastSession = session;
        if (ExceptionToThrow is not null)
        {
            throw ExceptionToThrow;
        }

        return Task.FromResult(Result);
    }
}
