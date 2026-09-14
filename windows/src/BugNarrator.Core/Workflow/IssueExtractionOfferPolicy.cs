namespace BugNarrator.Core.Workflow;

/// <summary>
/// Whether the session library shows the one-time "extract issues from your sessions?" offer. The
/// same rule as macOS SettingsStore.shouldShowIssueExtractionOfferBanner: only once the user has a
/// session to look at, only while automatic extraction is off, never after the offer has been made
/// (Turn On and Not Now both count), and only when the provider can actually extract — keyed off
/// capability rather than credential readiness, because a transcription-only provider must not be
/// offered a feature it cannot deliver.
/// </summary>
public static class IssueExtractionOfferPolicy
{
    public static bool ShouldShow(bool hasAnySession, bool autoExtractIssues, bool hasOffered, bool providerCanExtract)
    {
        return hasAnySession && !autoExtractIssues && !hasOffered && providerCanExtract;
    }
}
