using BugNarrator.Core.Models;
using BugNarrator.Core.Workflow;
using Xunit;

namespace BugNarrator.Core.Tests;

public sealed class SessionSummaryBuilderTests
{
    private static readonly TimeSpan Duration = TimeSpan.FromSeconds(125);
    private static readonly string Length = SessionTimeFormatter.FormatDuration(Duration);

    private static string Build(string transcript, int screenshots = 0, SessionTranscriptionStatus status = SessionTranscriptionStatus.Completed, string? failure = null) =>
        SessionSummaryBuilder.Build(transcript, status, failure, screenshots, Duration);

    [Theory]
    [InlineData("The button is dead. Then it recovered.", "The button is dead.")]
    [InlineData("Why is it dead? No idea.", "Why is it dead?")]
    [InlineData("It crashed! Twice.", "It crashed!")]
    public void LeadSentence_EndsAtTheFirstTerminatorFollowedBySpace(string transcript, string expectedLead)
    {
        Assert.StartsWith(expectedLead + " Session length", Build(transcript));
    }

    [Theory]
    [InlineData("Version 1.2 crashed on launch. Again later.", "Version 1.2 crashed on launch.")]
    [InlineData("Wait...what? Then nothing.", "Wait...what?")]
    [InlineData("Check config.yaml first. Then restart.", "Check config.yaml first.")]
    public void LeadSentence_DoesNotEndAtATerminatorInsideAToken(string transcript, string expectedLead)
    {
        // The break used to be the first '.', '!' or '?' anywhere: "Version 1." (#1194). A
        // terminator followed by whitespace still ends the sentence, so "Mr. Smith" is a known
        // limitation — abbreviation detection is a heuristic this builder does not attempt.
        Assert.StartsWith(expectedLead + " Session length", Build(transcript));
    }

    [Fact]
    public void LeadSentence_TerminatorAtEndOfTextCounts()
    {
        Assert.StartsWith("The button is dead. Session length", Build("  The button is dead.  "));
    }

    [Fact]
    public void NoTerminator_UnderTheCap_UsesTheWholeText()
    {
        Assert.StartsWith("the button is dead and stays dead Session length", Build("the button is dead and stays dead"));
    }

    [Fact]
    public void NoTerminator_OverTheCap_CutsAt220WithEllipsis()
    {
        var transcript = new string('a', 300);
        var summary = Build(transcript);
        Assert.StartsWith(new string('a', 220) + "... Session length", summary);
    }

    [Fact]
    public void TerminatorBeyondTheCap_FallsToTheCapPath()
    {
        var transcript = new string('b', 250) + ". Tail.";
        Assert.StartsWith(new string('b', 220) + "... Session length", Build(transcript));
    }

    [Theory]
    [InlineData(0, "0 screenshots")]
    [InlineData(1, "1 screenshot")]
    [InlineData(2, "2 screenshots")]
    public void TranscriptBranch_PluralisesScreenshots(int count, string phrase)
    {
        Assert.Equal($"Done. Session length {Length} with {phrase}.", Build("Done.", count));
    }

    [Fact]
    public void WhitespaceTranscript_FallsThroughToTheStatusBranches()
    {
        Assert.Equal($"Recording saved locally for {Length} with 3 screenshot artifacts.", Build("  \n ", 3));
    }

    [Fact]
    public void NotConfigured_PointsAtSettings()
    {
        Assert.Equal(
            $"Recording saved locally for {Length} with 1 screenshot artifacts. Finish AI provider setup in Settings to transcribe future sessions.",
            Build("", 1, SessionTranscriptionStatus.NotConfigured));
    }

    [Fact]
    public void Failed_CarriesTheFailureMessageOrAFallback()
    {
        Assert.Equal($"Recording saved locally for {Length}, but transcription failed. Disk full.", Build("", 0, SessionTranscriptionStatus.Failed, "Disk full."));
        Assert.Equal($"Recording saved locally for {Length}, but transcription failed. Review the saved audio and logs for details.", Build("", 0, SessionTranscriptionStatus.Failed));
    }
}
