namespace BugNarrator.Core.Models;

public sealed record JiraExportConfiguration(
    Uri BaseUrl,
    string Email,
    string ApiToken,
    string ProjectKey,
    string IssueType)
{
    public bool IsComplete =>
        BaseUrl is not null
        && !string.IsNullOrWhiteSpace(Email)
        && !string.IsNullOrWhiteSpace(ApiToken)
        && !string.IsNullOrWhiteSpace(ProjectKey)
        && !string.IsNullOrWhiteSpace(IssueType);
}
