using BugNarrator.Core.Export;
using Xunit;

namespace BugNarrator.Core.Tests;

/// <summary>Mirrors Tests/BugNarratorTests/TrackerExportPayloadBudgetTests.swift (#1200, macOS #1112).</summary>
public sealed class TrackerExportPayloadBudgetTests
{
    [Fact]
    public void TrackerTitle_PlainShortTitlePassesThroughUnchanged()
    {
        Assert.Equal("Login button stuck disabled", TrackerExportPayloadBudget.TrackerTitle("Login button stuck disabled", 255));
    }

    [Fact]
    public void TrackerTitle_CollapsesWhitespaceRunsAndNewlines()
    {
        Assert.Equal("Crash on launch after update", TrackerExportPayloadBudget.TrackerTitle("  Crash\r\non   launch\t\tafter\nupdate  ", 255));
    }

    [Theory]
    [InlineData(" \n\t ")]
    [InlineData("")]
    [InlineData(null)]
    public void TrackerTitle_WhitespaceOnlyBecomesEmpty(string? value)
    {
        Assert.Equal("", TrackerExportPayloadBudget.TrackerTitle(value, 255));
    }

    [Fact]
    public void TrackerTitle_ExactlyAtTheCapIsKeptWhole()
    {
        var title = new string('a', 255);
        Assert.Equal(title, TrackerExportPayloadBudget.TrackerTitle(title, 255));
    }

    [Fact]
    public void TrackerTitle_OneOverTheCapIsCutToTheCapEndingInAnEllipsis()
    {
        var result = TrackerExportPayloadBudget.TrackerTitle(new string('a', 256), 255);
        Assert.Equal(255, result.Length);
        Assert.Equal(new string('a', 254) + "…", result);
    }

    [Fact]
    public void TrackerTitle_CutDoesNotLeaveATrailingSpaceBeforeTheEllipsis()
    {
        Assert.Equal("a…", TrackerExportPayloadBudget.TrackerTitle("a bcd", 2));
        // "w " has period 2, so the last kept index (253, odd) is a space and must be trimmed.
        var result = TrackerExportPayloadBudget.TrackerTitle(string.Concat(Enumerable.Repeat("w ", 150)), 255);
        Assert.EndsWith("w…", result, System.StringComparison.Ordinal);
        Assert.Equal(254, result.Length);
    }

    [Fact]
    public void TrackerTitle_NeverCutsInsideASurrogatePair()
    {
        var title = "a" + string.Concat(Enumerable.Repeat("😀", 128)); // 257 UTF-16 units; unit 254 is a high surrogate
        var result = TrackerExportPayloadBudget.TrackerTitle(title, 255);

        Assert.False(char.IsHighSurrogate(result[^2]), "the cut must not leave a lone high surrogate before the ellipsis");
        Assert.EndsWith("😀…", result, System.StringComparison.Ordinal);
        Assert.True(result.Length <= 255);
    }

    [Fact]
    public void TrackerTitle_CollapsingHappensBeforeMeasuring()
    {
        Assert.Equal("short title", TrackerExportPayloadBudget.TrackerTitle("short" + new string(' ', 290) + "title", 255));
    }

    [Fact]
    public void TrackerTitle_HardLimitsMatchTheTrackers()
    {
        Assert.Equal(255, TrackerExportPayloadBudget.JiraSummaryLimit);
        Assert.Equal(256, TrackerExportPayloadBudget.GitHubTitleLimit);
    }

    [Fact]
    public void Truncated_OvershootsMaxCharactersBySuffixDesign()
    {
        // Cuts to max - 36 then appends a 47-character marker: pinned as the current contract,
        // shared with macOS, where every caller uses a self-imposed body budget with slack.
        var result = TrackerExportPayloadBudget.Truncated(new string('x', 1_000), 500);
        Assert.Equal(511, result.Length);
        Assert.EndsWith(" …[truncated by BugNarrator for tracker limits]", result, System.StringComparison.Ordinal);
    }

    [Fact]
    public void TrackerTitle_NeutralizesMentionsAndCrossReferences()
    {
        var title = TrackerExportPayloadBudget.TrackerTitle(
            "@security-team rotate #4821 keys GH-99",
            TrackerExportPayloadBudget.GitHubTitleLimit);

        // xUnit's string assertions normalize invisible characters away, so the zero-width
        // spaces are checked with plain string operations instead: a "does not contain"
        // assertion would pass even without them.
        Assert.True(title.Contains("@\u200B", StringComparison.Ordinal));
        Assert.True(title.Contains("#\u200B", StringComparison.Ordinal));
        Assert.True(title.Contains("GH-\u200B", StringComparison.Ordinal));
        // The text stays visually identical: only zero-width spaces are added.
        Assert.Equal(
            "@security-team rotate #4821 keys GH-99",
            title.Replace("\u200B", string.Empty, StringComparison.Ordinal));
    }

    [Fact]
    public void TrackerTitle_StillFitsTheTrackerCap()
    {
        // The zero-width spaces count towards the limit, so a title that was already at the cap
        // must not grow past it: the tracker rejects a title over 256 (GitHub) or 255 (Jira).
        //
        // The trailing "@" is the last character on purpose: if the neutralization ran after the
        // cap, the zero-width space it adds would push the title over the limit instead of being
        // cut away with it.
        var title = TrackerExportPayloadBudget.TrackerTitle(
            new string('a', 254) + "@",
            TrackerExportPayloadBudget.JiraSummaryLimit);

        Assert.True(
            title.Length <= TrackerExportPayloadBudget.JiraSummaryLimit,
            $"the title grew past the tracker limit: {title.Length}");
        Assert.EndsWith("…", title, System.StringComparison.Ordinal);
    }

    [Fact]
    public void TrackerTitle_CapCountsUTF16UnitsLikeTheTracker()
    {
        // Jira counts its 255-character limit in UTF-16 code units, so a title dense in
        // astral-plane characters is twice as long there as it is in characters.
        var title = TrackerExportPayloadBudget.TrackerTitle(
            string.Concat(Enumerable.Repeat("😀", 200)),
            TrackerExportPayloadBudget.JiraSummaryLimit);

        Assert.True(
            title.Length <= TrackerExportPayloadBudget.JiraSummaryLimit,
            $"the title grew past the tracker limit: {title.Length}");
    }

    [Fact]
    public void TrackerTitle_NeutralizesAMentionInsideAGraphemeCluster()
    {
        // The macOS port's literal search used to skip an "@" that was part of a larger
        // cluster, so both ports have to break the same mentions.
        var title = TrackerExportPayloadBudget.TrackerTitle(
            "@\u0301teamuser",
            TrackerExportPayloadBudget.GitHubTitleLimit);

        Assert.True(title.Contains("@\u200B", StringComparison.Ordinal));
        Assert.True(title.Contains("\u0301", StringComparison.Ordinal));
    }

    [Fact]
    public void TrackerTitle_DoesNotTrimALeadingZeroWidthSpace()
    {
        // Only the end of a cut title is trimmed, so a leading zero-width space survives
        // here and has to survive on the macOS port too.
        var title = TrackerExportPayloadBudget.TrackerTitle(
            "\u200B" + new string('a', 300),
            TrackerExportPayloadBudget.GitHubTitleLimit);

        Assert.True(
            title.StartsWith("\u200B", StringComparison.Ordinal),
            $"the leading zero-width space was trimmed away: {title}");
    }

    [Fact]
    public void TrackerTitle_TheCollapseDoesNotTreatAZeroWidthSpaceAsASeparator()
    {
        // Swift's whitespace set includes the zero-width space and .NET's does not, so a title
        // that carries one would collapse differently on the two ports. Both use one shared set
        // now.
        var title = TrackerExportPayloadBudget.TrackerTitle(
            "a\u200Bb",
            TrackerExportPayloadBudget.GitHubTitleLimit);

        // Plain string equality, because xUnit's Assert.Equal normalizes invisible characters
        // away and would pass even if the zero-width space were gone.
        Assert.True(title == "a\u200Bb", $"the collapse changed the title: {title}");
    }

    [Fact]
    public void TrackerTitle_LeavesATitleWithoutTriggersUnchanged()
    {
        Assert.Equal(
            "Login button stuck disabled",
            TrackerExportPayloadBudget.TrackerTitle(
                "Login button stuck disabled",
                TrackerExportPayloadBudget.GitHubTitleLimit));
    }

    [Fact]
    public void TrackerTitle_CutTrimsTheZeroWidthSpaceANeutralizedMentionLeavesBehind()
    {
        // macOS trims the zero-width space a neutralized mention leaves behind, and so must
        // Windows: otherwise the two ports send different titles for the same issue.
        var result = TrackerExportPayloadBudget.TrackerTitle("a@b c", 4);

        // Assert.True with plain string operations, because xUnit's Assert.Equal normalizes
        // invisible characters away and would pass even without the trim.
        Assert.True(
            !result.Contains("\u200B", StringComparison.Ordinal),
            $"a zero-width space survived the cut: {result}");
        Assert.True(
            result == "a@…",
            $"the cut did not match the macOS result: {result}");
    }
}
