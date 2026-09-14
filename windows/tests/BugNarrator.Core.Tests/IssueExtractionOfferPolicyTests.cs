using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class IssueExtractionOfferPolicyTests
{
    [Fact]
    public void ShouldShow_WhenThereIsASessionAutoExtractIsOffNotYetOfferedAndTheProviderCanExtract()
    {
        Assert.True(IssueExtractionOfferPolicy.ShouldShow(hasAnySession: true, autoExtractIssues: false, hasOffered: false, providerCanExtract: true));
    }

    [Fact]
    public void NotShown_BeforeAnySessionExists()
    {
        // The offer follows real work the user can see rather than greeting an empty library.
        Assert.False(IssueExtractionOfferPolicy.ShouldShow(hasAnySession: false, autoExtractIssues: false, hasOffered: false, providerCanExtract: true));
    }

    [Fact]
    public void NotShown_WhenAutomaticExtractionIsAlreadyOn()
    {
        Assert.False(IssueExtractionOfferPolicy.ShouldShow(hasAnySession: true, autoExtractIssues: true, hasOffered: false, providerCanExtract: true));
    }

    [Fact]
    public void NotShown_OnceItHasBeenOffered_WhicheverWayItWasAnswered()
    {
        // Not Now is permanent in the sense that the user is never asked again; they can still turn
        // automatic extraction on in Settings.
        Assert.False(IssueExtractionOfferPolicy.ShouldShow(hasAnySession: true, autoExtractIssues: false, hasOffered: true, providerCanExtract: true));
    }

    [Fact]
    public void NotShown_WhenTheProviderCannotExtract()
    {
        // Keyed off capability, not credential: a transcription-only provider must not be offered a
        // feature it cannot deliver.
        Assert.False(IssueExtractionOfferPolicy.ShouldShow(hasAnySession: true, autoExtractIssues: false, hasOffered: false, providerCanExtract: false));
    }
}
