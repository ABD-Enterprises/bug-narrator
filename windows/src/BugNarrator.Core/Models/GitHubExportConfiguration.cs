namespace BugNarrator.Core.Models;

public sealed record GitHubExportConfiguration(
    string Token,
    string Owner,
    string Repository,
    IReadOnlyList<string> Labels)
{
    public bool IsComplete =>
        !string.IsNullOrWhiteSpace(Token)
        && !string.IsNullOrWhiteSpace(Owner)
        && !string.IsNullOrWhiteSpace(Repository);
}
